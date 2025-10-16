defmodule Jump.Calendar.Client do
  @moduledoc """
  Google Calendar API client using GoogleApi.Calendar.V3 with OAuth token injection.
  """

  alias Jump.Accounts
  alias Jump.Auth.GoogleTokens
  require Logger

  @base_url "https://www.googleapis.com/calendar/v3"

  @doc """
  Get a Calendar API client with OAuth token for a user.
  Automatically refreshes the token if it's expired or expiring soon.
  """
  def get_conn(user_id) do
    case Accounts.get_oauth_account(user_id, :google) do
      {:ok, oauth_account} ->
        # Refresh token if needed (expires within 5 min)
        case GoogleTokens.refresh_if_needed(oauth_account) do
          {:ok, refreshed_account} ->
            {:ok, build_conn(refreshed_account.access_token)}

          {:error, reason} ->
            Logger.error("Failed to refresh Google token for user #{user_id}: #{inspect(reason)}")
            {:error, reason}
        end

      {:error, :not_found} ->
        {:error, :google_not_connected}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Build a GoogleApi Calendar connection with OAuth token.
  """
  def build_conn(access_token) do
    GoogleApi.Calendar.V3.Connection.new(access_token)
  end

  @doc """
  List calendars available to the user.
  """
  def list_calendars(conn, opts \\ []) do
    max_results = Keyword.get(opts, :max_results, 250)
    page_token = Keyword.get(opts, :page_token, nil)

    params = %{
      "maxResults" => max_results
    }

    params =
      if page_token do
        Map.put(params, "pageToken", page_token)
      else
        params
      end

    case GoogleApi.Calendar.V3.Api.CalendarList.calendar_calendar_list_list(conn, params) do
      {:ok, response} ->
        {:ok,
         %{
           calendars: response.items || [],
           next_page_token: response.nextPageToken,
           sync_token: response.nextSyncToken
         }}

      {:error, %{status: status, body: body}} ->
        Logger.error("Failed to list calendars: #{status} - #{inspect(body)}")
        {:error, {:api_error, status, body}}

      {:error, reason} ->
        Logger.error("Failed to list calendars: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Get the primary calendar for the user.
  """
  def get_primary_calendar(conn) do
    case GoogleApi.Calendar.V3.Api.Calendars.calendar_calendars_get(conn, "primary") do
      {:ok, calendar} ->
        {:ok, calendar}

      {:error, %{status: status, body: body}} ->
        Logger.error("Failed to get primary calendar: #{status} - #{inspect(body)}")
        {:error, {:api_error, status, body}}

      {:error, reason} ->
        Logger.error("Failed to get primary calendar: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Query free/busy information for a user and date range.
  """
  def get_free_busy(conn, user_id, time_min, time_max, calendar_ids \\ nil, opts \\ []) do
    calendar_ids = calendar_ids || ["primary"]

    # Convert DateTime to ISO8601 format with timezone
    time_min_str = format_time_for_api(time_min)
    time_max_str = format_time_for_api(time_max)

    # Build the free/busy request
    free_busy_request = %{
      "timeMin" => time_min_str,
      "timeMax" => time_max_str,
      "items" => Enum.map(calendar_ids, &%{"id" => &1}),
      "timeZone" => Keyword.get(opts, :timezone, "UTC")
    }

    case GoogleApi.Calendar.V3.Api.Freebusy.calendar_freebusy_query(conn, body: free_busy_request) do
      {:ok, response} ->
        {:ok,
         %{
           calendars: response.calendars || %{},
           group: response.group,
           time_min: time_min,
           time_max: time_max
         }}

      {:error, %{status: status, body: body}} ->
        Logger.error("Failed to query free/busy: #{status} - #{inspect(body)}")
        {:error, {:api_error, status, body}}

      {:error, reason} ->
        Logger.error("Failed to query free/busy: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  List events in a calendar with optional filtering.
  """
  def list_events(conn, calendar_id \\ "primary", opts \\ []) do
    time_min = Keyword.get(opts, :time_min)
    time_max = Keyword.get(opts, :time_max)
    max_results = Keyword.get(opts, :max_results, 250)
    page_token = Keyword.get(opts, :page_token, nil)
    sync_token = Keyword.get(opts, :sync_token, nil)
    single_events = Keyword.get(opts, :single_events, true)
    order_by = Keyword.get(opts, :order_by, "startTime")

    params = %{
      "maxResults" => max_results,
      "singleEvents" => single_events,
      "orderBy" => order_by
    }

    params =
      cond do
        sync_token ->
          Map.put(params, "syncToken", sync_token)

        time_min ->
          params
          |> Map.put("timeMin", format_time_for_api(time_min))
          |> put_if(time_max, "timeMax", format_time_for_api(time_max))

        true ->
          params
      end

    params =
      if page_token do
        Map.put(params, "pageToken", page_token)
      else
        params
      end

    case GoogleApi.Calendar.V3.Api.Events.calendar_events_list(
           conn,
           calendar_id,
           Map.to_list(params)
         ) do
      {:ok, response} ->
        {:ok,
         %{
           events: response.items || [],
           next_page_token: response.nextPageToken,
           next_sync_token: response.nextSyncToken,
           time_zone: response.timeZone,
           default_reminders: response.defaultReminders
         }}

      {:error, %{status: status, body: body}} ->
        Logger.error("Failed to list events: #{status} - #{inspect(body)}")
        {:error, {:api_error, status, body}}

      {:error, reason} ->
        Logger.error("Failed to list events: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Create a new event in the calendar.
  """
  def create_event(conn, calendar_id \\ "primary", event_params) do
    event = build_event_model(event_params)

    case GoogleApi.Calendar.V3.Api.Events.calendar_events_insert(conn, calendar_id, body: event) do
      {:ok, created_event} ->
        Logger.info("Successfully created calendar event: #{created_event.id}")
        {:ok, created_event}

      {:error, %{status: status, body: body}} ->
        Logger.error("Failed to create calendar event: #{status} - #{inspect(body)}")
        {:error, {:api_error, status, body}}

      {:error, reason} ->
        Logger.error("Failed to create calendar event: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Update an existing event.
  """
  def update_event(conn, calendar_id \\ "primary", event_id, event_params) do
    event = build_event_model(event_params)

    case GoogleApi.Calendar.V3.Api.Events.calendar_events_update(conn, calendar_id, event_id,
           body: event
         ) do
      {:ok, updated_event} ->
        Logger.info("Successfully updated calendar event: #{updated_event.id}")
        {:ok, updated_event}

      {:error, %{status: status, body: body}} ->
        Logger.error("Failed to update calendar event: #{status} - #{inspect(body)}")
        {:error, {:api_error, status, body}}

      {:error, reason} ->
        Logger.error("Failed to update calendar event: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Delete an event from the calendar.
  """
  def delete_event(conn, calendar_id \\ "primary", event_id, opts \\ []) do
    send_updates = Keyword.get(opts, :send_updates, "all")

    params = if send_updates != "all", do: %{"sendUpdates" => send_updates}, else: %{}

    case GoogleApi.Calendar.V3.Api.Events.calendar_events_delete(
           conn,
           calendar_id,
           event_id,
           params
         ) do
      :ok ->
        Logger.info("Successfully deleted calendar event: #{event_id}")
        :ok

      {:error, %{status: status, body: body}} ->
        Logger.error("Failed to delete calendar event: #{status} - #{inspect(body)}")
        {:error, {:api_error, status, body}}

      {:error, reason} ->
        Logger.error("Failed to delete calendar event: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Set up push notifications (webhooks) for calendar changes.
  """
  def watch_events(conn, calendar_id \\ "primary", webhook_url, opts \\ []) do
    watch_request = %{
      "id" => generate_channel_id(),
      "type" => "web_hook",
      "address" => webhook_url
    }

    # Add optional parameters
    watch_request =
      watch_request
      |> put_if(opts[:token], "token", opts[:token])
      |> put_if(opts[:ttl], "ttl", opts[:ttl])

    case GoogleApi.Calendar.V3.Api.Events.calendar_events_watch(conn, calendar_id,
           body: watch_request
         ) do
      {:ok, response} ->
        Logger.info("Successfully set up calendar watch for #{calendar_id}")
        {:ok, response}

      {:error, %{status: status, body: body}} ->
        Logger.error("Failed to set up calendar watch: #{status} - #{inspect(body)}")
        {:error, {:api_error, status, body}}

      {:error, reason} ->
        Logger.error("Failed to set up calendar watch: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Stop watching for calendar changes.
  """
  def stop_watch(conn, channel_id, resource_id) do
    stop_request = %{
      "id" => channel_id,
      "resourceId" => resource_id
    }

    case GoogleApi.Calendar.V3.Api.Channels.calendar_channels_stop(conn, body: stop_request) do
      :ok ->
        Logger.info("Successfully stopped calendar watch: #{channel_id}")
        :ok

      {:error, %{status: status, body: body}} ->
        Logger.error("Failed to stop calendar watch: #{status} - #{inspect(body)}")
        {:error, {:api_error, status, body}}

      {:error, reason} ->
        Logger.error("Failed to stop calendar watch: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Private functions

  defp build_event_model(params) do
    # Build base event structure
    event = %{}

    # Add basic fields
    event = put_if(event, params[:summary], "summary", params[:summary])
    event = put_if(event, params[:description], "description", params[:description])
    event = put_if(event, params[:location], "location", params[:location])

    # Add timing
    event =
      case params[:start] do
        nil ->
          event

        start_time ->
          start_data = build_time_data(start_time, params[:start_timezone])
          Map.put(event, "start", start_data)
      end

    event =
      case params[:end] do
        nil ->
          event

        end_time ->
          end_data = build_time_data(end_time, params[:end_timezone])
          Map.put(event, "end", end_data)
      end

    # Add attendees
    event =
      case params[:attendees] do
        nil ->
          event

        attendees when is_list(attendees) ->
          attendee_data = Enum.map(attendees, &build_attendee_data/1)
          Map.put(event, "attendees", attendee_data)

        _ ->
          event
      end

    # Add conference data (Google Meet)
    event =
      if params[:conference] do
        conference_data = %{
          "createRequest" => %{
            "requestId" => generate_request_id(),
            "conferenceSolutionKey" => %{"type" => "hangoutsMeet"}
          }
        }

        Map.put(event, "conferenceData", conference_data)
      else
        event
      end

    # Add other optional fields
    event = put_if(event, params[:visibility], "visibility", params[:visibility])
    event = put_if(event, params[:transparency], "transparency", params[:transparency])

    event =
      put_if(
        event,
        params[:guests_can_invite_others],
        "guestsCanInviteOthers",
        params[:guests_can_invite_others]
      )

    event =
      put_if(event, params[:guests_can_modify], "guestsCanModify", params[:guests_can_modify])

    event =
      put_if(
        event,
        params[:guests_can_see_other_guests],
        "guestsCanSeeOtherGuests",
        params[:guests_can_see_other_guests]
      )

    # Add reminders
    event =
      case params[:reminders] do
        nil ->
          event

        reminders when is_list(reminders) ->
          reminder_data = Enum.map(reminders, &build_reminder_data/1)
          Map.put(event, "reminders", %{"overrides" => reminder_data, "useDefault" => false})

        _ ->
          event
      end

    event
  end

  defp build_time_data(time, timezone \\ nil) do
    case time do
      %DateTime{} ->
        if timezone do
          %{"dateTime" => DateTime.to_iso8601(time), "timeZone" => timezone}
        else
          %{"dateTime" => DateTime.to_iso8601(time)}
        end

      %Date{} ->
        %{"date" => Date.to_iso8601(time)}

      time_str when is_binary(time_str) ->
        # Try to parse as ISO8601
        case DateTime.from_iso8601(time_str) do
          {:ok, dt, _} ->
            if timezone do
              %{"dateTime" => time_str, "timeZone" => timezone}
            else
              %{"dateTime" => time_str}
            end

          {:error, :invalid_format} ->
            # Try to parse as date
            case Date.from_iso8601(time_str) do
              {:ok, date} -> %{"date" => time_str}
              {:error, _} -> %{"dateTime" => time_str}
            end
        end

      _ ->
        %{"dateTime" => to_string(time)}
    end
  end

  defp build_attendee_data(attendee) when is_binary(attendee) do
    %{"email" => attendee}
  end

  defp build_attendee_data(attendee) when is_map(attendee) do
    data = %{"email" => attendee[:email] || attendee["email"]}

    data =
      put_if(
        data,
        attendee[:display_name] || attendee["displayName"],
        "displayName",
        attendee[:display_name] || attendee["displayName"]
      )

    data = put_if(data, attendee[:response_status], "responseStatus", attendee[:response_status])
    data = put_if(data, attendee[:optional], "optional", attendee[:optional])
    data = put_if(data, attendee[:comment], "comment", attendee[:comment])

    data
  end

  defp build_reminder_data(reminder) when is_map(reminder) do
    data = %{"method" => reminder[:method] || reminder["method"] || "popup"}

    case reminder[:minutes] || reminder["minutes"] do
      nil -> data
      minutes -> Map.put(data, "minutes", minutes)
    end
  end

  defp build_reminder_data(reminder) when is_binary(reminder) do
    %{"method" => reminder}
  end

  defp format_time_for_api(%DateTime{} = time) do
    DateTime.to_iso8601(time)
  end

  defp format_time_for_api(time_str) when is_binary(time_str) do
    time_str
  end

  defp format_time_for_api(%Date{} = date) do
    Date.to_iso8601(date)
  end

  defp put_if(map, nil, _key, _value), do: map
  defp put_if(map, value, key, _value) when value == "", do: map
  defp put_if(map, _value, key, value), do: Map.put(map, key, value)

  defp generate_channel_id do
    "jump-calendar-#{:crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)}"
  end

  defp generate_request_id do
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  end
end
