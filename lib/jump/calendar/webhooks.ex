defmodule Jump.Calendar.Webhooks do
  @moduledoc """
  Handles Google Calendar webhook setup, validation, and processing.
  """

  alias Jump.Calendar.Client
  alias Jump.Sync.CalendarCursor
  alias Jump.Repo
  import Ecto.Query
  require Logger

  # 7 days
  @webhook_ttl_seconds 604_800
  # 1 day before expiration
  @renewal_threshold_seconds 86400

  @doc """
  Set up webhook notifications for a user's calendar.
  """
  def setup_webhook(user_id, calendar_id \\ "primary", webhook_url, opts \\ []) do
    timezone = Keyword.get(opts, :timezone, "UTC")

    with {:ok, conn} <- Client.get_conn(user_id) do
      # Generate unique webhook address for this user/calendar
      user_webhook_url = build_user_webhook_url(webhook_url, user_id, calendar_id)

      case Client.watch_events(conn, calendar_id, user_webhook_url, ttl: @webhook_ttl_seconds) do
        {:ok, watch_response} ->
          # Store watch information
          cursor_params = %{
            user_id: user_id,
            calendar_id: calendar_id,
            channel_id: watch_response.id,
            resource_id: watch_response.resourceId,
            channel_expiration: parse_expiration_time(watch_response.expiration),
            # Will be set after first sync
            sync_token: nil
          }

          case create_or_update_calendar_cursor(cursor_params) do
            {:ok, cursor} ->
              Logger.info(
                "Successfully set up calendar webhook for user #{user_id}, calendar #{calendar_id}"
              )

              # Trigger initial sync to get sync token
              trigger_initial_sync(user_id, calendar_id, timezone)

              {:ok, cursor}

            {:error, reason} ->
              Logger.error("Failed to store calendar cursor: #{inspect(reason)}")
              # Try to clean up the watch
              cleanup_watch(conn, watch_response.id, watch_response.resourceId)
              {:error, reason}
          end

        error ->
          error
      end
    else
      error -> error
    end
  end

  @doc """
  Remove webhook notifications for a user's calendar.
  """
  def remove_webhook(user_id, calendar_id \\ "primary") do
    case get_calendar_cursor(user_id, calendar_id) do
      nil ->
        {:error, :webhook_not_found}

      cursor ->
        with {:ok, conn} <- Client.get_conn(user_id) do
          case Client.stop_watch(conn, cursor.channel_id, cursor.resource_id) do
            :ok ->
              # Remove the cursor record
              Repo.delete(cursor)

              Logger.info(
                "Successfully removed calendar webhook for user #{user_id}, calendar #{calendar_id}"
              )

              :ok

            error ->
              error
          end
        else
          error -> error
        end
    end
  end

  @doc """
  Renew webhook notifications before expiration.
  """
  def renew_webhook(user_id, calendar_id \\ "primary", webhook_url) do
    # Remove existing webhook
    remove_webhook(user_id, calendar_id)

    # Set up new webhook
    setup_webhook(user_id, calendar_id, webhook_url)
  end

  @doc """
  Validate Google Calendar webhook notification.
  """
  def validate_webhook_notification(headers, body) do
    with {:ok, channel_id} <- get_header(headers, "x-goog-channel-id"),
         {:ok, resource_id} <- get_header(headers, "x-goog-resource-id"),
         {:ok, resource_state} <- get_header(headers, "x-goog-resource-state"),
         {:ok, resource_uri} <- get_header(headers, "x-goog-resource-uri") do
      notification_data = %{
        channel_id: channel_id,
        resource_id: resource_id,
        resource_state: resource_state,
        resource_uri: resource_uri,
        headers: headers,
        body: body
      }

      # Find the cursor for this webhook
      case find_cursor_by_channel(channel_id, resource_id) do
        nil ->
          {:error, :webhook_not_found}

        cursor ->
          {:ok, Map.put(notification_data, :cursor, cursor)}
      end
    else
      error -> error
    end
  end

  @doc """
  Process a calendar webhook notification.
  """
  def process_webhook_notification(notification_data) do
    cursor = notification_data.cursor
    resource_state = notification_data.resource_state

    case resource_state do
      "sync" ->
        # Initial sync or webhook reconnection
        handle_sync_notification(cursor, notification_data)

      "exists" ->
        # Calendar change detected
        handle_change_notification(cursor, notification_data)

      "not_exists" ->
        # Calendar deleted or permission revoked
        handle_deletion_notification(cursor, notification_data)

      _ ->
        Logger.warning("Unknown resource state in calendar webhook: #{resource_state}")
        :ok
    end
  end

  @doc """
  Get active webhooks for a user.
  """
  def get_user_webhooks(user_id) do
    CalendarCursor
    |> where([c], c.user_id == ^user_id and not is_nil(c.channel_id))
    |> Repo.all()
  end

  @doc """
  Check if webhooks need renewal and auto-renew if necessary.
  """
  def check_and_renew_webhooks(webhook_url) do
    expiring_soon = DateTime.add(DateTime.utc_now(), @renewal_threshold_seconds, :second)

    CalendarCursor
    |> where([c], c.channel_expiration <= ^expiring_soon and not is_nil(c.channel_id))
    |> Repo.all()
    |> Enum.each(fn cursor ->
      Logger.info("Renewing expiring calendar webhook for user #{cursor.user_id}")

      case renew_webhook(cursor.user_id, cursor.calendar_id, webhook_url) do
        {:ok, _} ->
          Logger.info("Successfully renewed calendar webhook for user #{cursor.user_id}")

        {:error, reason} ->
          Logger.error(
            "Failed to renew calendar webhook for user #{cursor.user_id}: #{inspect(reason)}"
          )
      end
    end)
  end

  # Private functions

  defp build_user_webhook_url(base_url, user_id, calendar_id) do
    "#{base_url}/#{user_id}/#{calendar_id}"
  end

  defp create_or_update_calendar_cursor(params) do
    case get_calendar_cursor(params.user_id, params.calendar_id) do
      nil ->
        %CalendarCursor{}
        |> CalendarCursor.changeset(params)
        |> Repo.insert()

      cursor ->
        cursor
        |> CalendarCursor.changeset(params)
        |> Repo.update()
    end
  end

  defp get_calendar_cursor(user_id, calendar_id) do
    CalendarCursor
    |> where([c], c.user_id == ^user_id and c.calendar_id == ^calendar_id)
    |> Repo.one()
  end

  defp find_cursor_by_channel(channel_id, resource_id) do
    CalendarCursor
    |> where([c], c.channel_id == ^channel_id and c.resource_id == ^resource_id)
    |> Repo.one()
  end

  defp parse_expiration_time(expiration_str) when is_binary(expiration_str) do
    case DateTime.from_iso8601(expiration_str) do
      {:ok, dt, _} ->
        dt

      {:error, _} ->
        # Try parsing as Unix timestamp
        case Integer.parse(expiration_str) do
          {timestamp, ""} -> DateTime.from_unix!(timestamp)
          _ -> DateTime.add(DateTime.utc_now(), @webhook_ttl_seconds, :second)
        end
    end
  end

  defp parse_expiration_time(nil) do
    DateTime.add(DateTime.utc_now(), @webhook_ttl_seconds, :second)
  end

  defp cleanup_watch(conn, channel_id, resource_id) do
    Client.stop_watch(conn, channel_id, resource_id)
  rescue
    error ->
      Logger.error("Failed to cleanup calendar watch: #{inspect(error)}")
  end

  defp trigger_initial_sync(user_id, calendar_id, timezone) do
    # Enqueue sync job
    case Jump.Workers.CalendarSync.new(%{
           "user_id" => user_id,
           "calendar_id" => calendar_id,
           "timezone" => timezone,
           "full_sync" => true
         }) do
      {:ok, job} ->
        Oban.insert(job)

      {:error, reason} ->
        Logger.error("Failed to enqueue calendar sync job: #{inspect(reason)}")
    end
  end

  defp handle_sync_notification(cursor, notification_data) do
    Logger.info(
      "Calendar sync notification for user #{cursor.user_id}, calendar #{cursor.calendar_id}"
    )

    # Trigger full sync to establish sync token
    trigger_sync_for_cursor(cursor, notification_data, full_sync: true)
  end

  defp handle_change_notification(cursor, notification_data) do
    Logger.info(
      "Calendar change notification for user #{cursor.user_id}, calendar #{cursor.calendar_id}"
    )

    # Trigger incremental sync using sync token
    trigger_sync_for_cursor(cursor, notification_data, full_sync: false)
  end

  defp handle_deletion_notification(cursor, _notification_data) do
    Logger.warning(
      "Calendar deletion notification for user #{cursor.user_id}, calendar #{cursor.calendar_id}"
    )

    # Remove the webhook since calendar is no longer accessible
    Repo.delete(cursor)
  end

  defp trigger_sync_for_cursor(cursor, notification_data, opts) do
    full_sync = Keyword.get(opts, :full_sync, false)

    # Extract timezone from notification or use default
    timezone = extract_timezone_from_notification(notification_data) || "UTC"

    case Jump.Workers.CalendarSync.new(%{
           "user_id" => cursor.user_id,
           "calendar_id" => cursor.calendar_id,
           "timezone" => timezone,
           "full_sync" => full_sync,
           "sync_token" => if(full_sync, do: nil, else: cursor.sync_token)
         }) do
      {:ok, job} ->
        Oban.insert(job)

      {:error, reason} ->
        Logger.error("Failed to enqueue calendar sync job: #{inspect(reason)}")
    end
  end

  defp extract_timezone_from_notification(_notification_data) do
    # In a real implementation, you might extract timezone from the notification
    # or fetch it from user preferences
    nil
  end

  defp get_header(headers, key) do
    case Enum.find(headers, fn {k, _} -> String.downcase(k) == String.downcase(key) end) do
      {_, value} -> {:ok, value}
      nil -> {:error, :missing_header}
    end
  end
end
