defmodule Jump.Workers.CalendarSync do
  @moduledoc """
  Oban worker for synchronizing Google Calendar data.
  """

  use Oban.Worker, queue: :sync, max_attempts: 3, unique: [period: 300]

  alias Jump.Calendar.Client
  alias Jump.Calendar.Chunker
  alias Jump.Sync.CalendarCursor
  alias Jump.RAG
  alias Jump.Repo
  import Ecto.Query
  require Logger

  @max_sync_results 250
  @rate_limit_delay_ms 200

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"user_id" => user_id}}) do
    # Default to primary calendar when calendar_id not provided
    perform_with_calendar(user_id, "primary", %{"full_sync" => false})
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"user_id" => user_id, "calendar_id" => calendar_id} = args}) do
    perform_with_calendar(user_id, calendar_id, args)
  end

  defp perform_with_calendar(user_id, calendar_id, args) do
    timezone = Map.get(args, "timezone", "UTC")
    full_sync = Map.get(args, "full_sync", false)
    sync_token = Map.get(args, "sync_token")

    Logger.info(
      "Starting calendar sync for user #{user_id}, calendar #{calendar_id}, full_sync: #{full_sync}"
    )

    case Client.get_conn(user_id) do
      {:ok, conn} ->
        sync_calendar(conn, user_id, calendar_id, timezone, full_sync, sync_token)

      {:error, reason} ->
        Logger.error("Failed to get Calendar connection for user #{user_id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Private functions

  defp sync_calendar(conn, user_id, calendar_id, timezone, full_sync, sync_token) do
    try do
      # Get the current cursor for this calendar
      cursor = get_or_create_cursor(user_id, calendar_id)

      # Determine sync parameters
      sync_params = build_sync_params(full_sync, sync_token, cursor, timezone)

      # Fetch events from Calendar API
      case Client.list_events(conn, calendar_id, sync_params) do
        {:ok, response} ->
          # Process the events
          case process_synced_events(response, user_id, calendar_id, timezone) do
            {:ok, processed_count} ->
              # Update cursor with new sync token
              update_cursor_sync_token(cursor, response.next_sync_token)

              Logger.info(
                "Successfully synced #{processed_count} calendar events for user #{user_id}"
              )

              :ok

            {:error, reason} ->
              Logger.error("Failed to process synced events: #{inspect(reason)}")
              {:error, reason}
          end

        {:error, {:api_error, 410, _}} ->
          # Sync token expired, need full sync
          Logger.warning("Sync token expired for user #{user_id}, performing full sync")
          sync_calendar(conn, user_id, calendar_id, timezone, true, nil)

        {:error, reason} ->
          Logger.error("Failed to fetch calendar events: #{inspect(reason)}")
          {:error, reason}
      end
    rescue
      error ->
        Logger.error("Calendar sync failed for user #{user_id}: #{inspect(error)}")
        {:error, error}
    end
  end

  defp get_or_create_cursor(user_id, calendar_id) do
    case CalendarCursor
         |> where([c], c.user_id == ^user_id and c.calendar_id == ^calendar_id)
         |> Repo.one() do
      nil ->
        %CalendarCursor{}
        |> CalendarCursor.changeset(%{
          user_id: user_id,
          calendar_id: calendar_id,
          sync_token: nil
        })
        |> Repo.insert!()

      cursor ->
        cursor
    end
  end

  defp build_sync_params(full_sync, sync_token, cursor, timezone) do
    base_params = [
      max_results: @max_sync_results,
      single_events: true,
      order_by: "startTime"
    ]

    params =
      cond do
        full_sync ->
          # For full sync, don't use sync token, get recent events
          # 30 days ago
          time_min = DateTime.add(DateTime.utc_now(), -30 * 24 * 60 * 60, :second)
          Keyword.put(base_params, :time_min, time_min)

        sync_token ->
          # Use the provided sync token for incremental sync
          Keyword.put(base_params, :sync_token, sync_token)

        cursor.sync_token ->
          # Use stored sync token
          Keyword.put(base_params, :sync_token, cursor.sync_token)

        true ->
          # No sync token available, do a limited sync
          # 7 days ago
          time_min = DateTime.add(DateTime.utc_now(), -7 * 24 * 60 * 60, :second)
          Keyword.put(base_params, :time_min, time_min)
      end

    # Add timezone if specified
    if timezone && timezone != "UTC" do
      Keyword.put(params, :time_zone, timezone)
    else
      params
    end
  end

  defp process_synced_events(response, user_id, calendar_id, timezone) do
    events = response.events || []

    Logger.debug("Processing #{length(events)} calendar events for user #{user_id}")

    # Process each event
    processed_events =
      events
      |> Enum.map(fn event ->
        process_single_event(event, user_id, calendar_id, timezone)
      end)
      |> Enum.filter(&match?({:ok, _}, &1))
      |> Enum.map(fn {:ok, processed} -> processed end)

    # Store or update events in the database
    case store_calendar_events(processed_events, user_id, calendar_id) do
      {:ok, stored_count} ->
        # Trigger any additional processing
        trigger_event_processing(processed_events, user_id, calendar_id)
        {:ok, stored_count}

      error ->
        error
    end
  end

  defp process_single_event(event, user_id, calendar_id, timezone) do
    try do
      processed_event = %{
        user_id: user_id,
        calendar_id: calendar_id,
        event_id: event.id,
        ical_uid: event.iCalUID,
        summary: event.summary,
        description: event.description,
        location: event.location,
        status: event.status,
        visibility: event.visibility,
        transparency: event.transparency,
        start_time: parse_event_time(event.start, timezone),
        end_time: parse_event_time(event.end, timezone),
        attendees: parse_attendees(event.attendees),
        recurrence: event.recurrence,
        recurring_event_id: event.recurringEventId,
        original_start_time: parse_event_time(event.originalStartTime, timezone),
        conference_data: event.conferenceData,
        attachments: event.attachments,
        creator: parse_person(event.creator),
        organizer: parse_person(event.organizer),
        created_at: parse_datetime(event.created),
        updated_at: parse_datetime(event.updated),
        html_link: event.htmlLink,
        hangout_link: event.hangoutLink,
        sequence: event.sequence,
        extended_properties: event.extendedProperties,
        reminders: parse_reminders(event.reminders)
      }

      {:ok, processed_event}
    rescue
      error ->
        Logger.error("Failed to process calendar event #{event.id}: #{inspect(error)}")
        {:error, error}
    end
  end

  defp parse_event_time(nil, _timezone), do: nil

  defp parse_event_time(time_data, timezone) when is_map(time_data) do
    cond do
      Map.has_key?(time_data, "dateTime") ->
        case DateTime.from_iso8601(time_data["dateTime"]) do
          {:ok, dt, _} -> dt
          {:error, _} -> nil
        end

      Map.has_key?(time_data, "date") ->
        case Date.from_iso8601(time_data["date"]) do
          {:ok, date} ->
            DateTime.new!(date, ~T[00:00:00])

          {:error, _} ->
            nil
        end

      true ->
        nil
    end
  end

  defp parse_event_time(_, _timezone), do: nil

  defp parse_attendees(nil), do: []

  defp parse_attendees(attendees) when is_list(attendees) do
    Enum.map(attendees, fn attendee ->
      %{
        email: Map.get(attendee, "email"),
        display_name: Map.get(attendee, "displayName"),
        response_status: Map.get(attendee, "responseStatus"),
        comment: Map.get(attendee, "comment"),
        optional: Map.get(attendee, "optional", false),
        organizer: Map.get(attendee, "organizer", false),
        resource: Map.get(attendee, "resource", false)
      }
    end)
  end

  defp parse_person(nil), do: nil

  defp parse_person(person) when is_map(person) do
    %{
      id: Map.get(person, "id"),
      email: Map.get(person, "email"),
      display_name: Map.get(person, "displayName"),
      self: Map.get(person, "self", false)
    }
  end

  defp parse_datetime(nil), do: nil

  defp parse_datetime(datetime_str) when is_binary(datetime_str) do
    case DateTime.from_iso8601(datetime_str) do
      {:ok, dt, _} -> dt
      {:error, _} -> nil
    end
  end

  defp parse_reminders(nil), do: nil

  defp parse_reminders(reminders) when is_map(reminders) do
    %{
      use_default: Map.get(reminders, "useDefault", false),
      overrides: Map.get(reminders, "overrides", [])
    }
  end

  defp store_calendar_events(processed_events, user_id, calendar_id) do
    # This would typically store events in a calendar_events table
    # For now, we'll just count and log them
    count = length(processed_events)

    Logger.info("Stored #{count} calendar events for user #{user_id}, calendar #{calendar_id}")

    # In a full implementation, you would:
    # 1. Upsert events into a calendar_events table
    # 2. Handle event deletions (events that are no longer present)
    # 3. Update event metadata and relationships

    {:ok, count}
  end

  defp trigger_event_processing(processed_events, user_id, calendar_id) do
    # Trigger additional processing for events
    Enum.each(processed_events, fn event ->
      # Example: Process upcoming events for notifications
      if should_send_notification?(event) do
        enqueue_notification_processing(event, user_id, calendar_id)
      end

      # Example: Update RAG with event content
      if should_index_for_rag?(event) do
        enqueue_rag_processing(event, user_id, calendar_id)
      end
    end)
  end

  defp should_send_notification?(event) do
    # Logic to determine if event should trigger notifications
    # Example: events happening in next 24 hours
    now = DateTime.utc_now()
    event_start = event.start_time

    event_start &&
      DateTime.compare(event_start, now) == :gt &&
      DateTime.diff(event_start, now, :second) <= 24 * 60 * 60
  end

  defp should_index_for_rag?(event) do
    # Index events that have meaningful content
    has_summary = event.summary && String.length(event.summary) > 0
    has_description = event.description && String.length(event.description) > 0
    has_attendees = length(event.attendees) > 0
    is_future = event.start_time && DateTime.compare(event.start_time, DateTime.utc_now()) == :gt

    # Index if: has summary AND (has description OR has attendees OR is upcoming)
    has_summary && (has_description || has_attendees || is_future)
  end

  defp enqueue_notification_processing(event, user_id, calendar_id) do
    # This would enqueue a notification processing job
    Logger.debug("Would enqueue notification processing for event #{event.event_id}")
  end

  defp enqueue_rag_processing(event, user_id, calendar_id) do
    Logger.debug("Enqueuing RAG processing for calendar event #{event.event_id}")

    # Create RAG chunks from the event
    chunks = Chunker.create_rag_chunks(event, user_id)

    if Enum.empty?(chunks) do
      Logger.debug("No chunks created for calendar event #{event.event_id}")
    else
      # Store chunks and schedule embeddings
      Enum.each(chunks, fn chunk_attrs ->
        case RAG.create_chunk(chunk_attrs) do
          {:ok, chunk} ->
            # Schedule embedding for this chunk
            schedule_embedding(chunk.id)
            Logger.debug("Created and scheduled embedding for calendar chunk #{chunk.id}")

          {:error, reason} ->
            Logger.error("Failed to create calendar chunk: #{inspect(reason)}")
        end
      end)
    end
  end

  defp schedule_embedding(chunk_id) do
    %{"chunk_id" => chunk_id}
    |> Jump.Workers.EmbedChunk.new(queue: :embed)
    |> Oban.insert()
  end

  defp update_cursor_sync_token(cursor, nil), do: cursor

  defp update_cursor_sync_token(cursor, sync_token) do
    cursor
    |> CalendarCursor.changeset(%{sync_token: sync_token})
    |> Repo.update()
  end
end
