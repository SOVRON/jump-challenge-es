defmodule Jump.Calendar.Events do
  @moduledoc """
  Handles calendar event creation, updates, and management.
  """

  alias Jump.Calendar.Client
  alias Jump.Accounts
  require Logger

  # Default reminders 15 min and 1 hour before
  @default_reminder_minutes [15, 60]
  @default_visibility "default"
  @default_transparency "opaque"

  @doc """
  Create a new calendar event.
  """
  def create_event(user_id, event_params, opts \\ []) do
    calendar_id = Keyword.get(opts, :calendar_id, "primary")
    send_updates = Keyword.get(opts, :send_updates, "all")

    with {:ok, conn} <- Client.get_conn(user_id),
         :ok <- validate_event_params(event_params) do
      # Build event with defaults
      event_data = build_event_with_defaults(event_params)

      # Add optional parameters
      event_data =
        event_data
        |> Map.put(:send_updates, send_updates)
        |> put_if(opts[:attendees], :attendees, opts[:attendees])
        |> put_if(opts[:conference], :conference, opts[:conference])

      case Client.create_event(conn, calendar_id, event_data) do
        {:ok, created_event} ->
          # Log audit event
          log_calendar_action(user_id, "event_created", %{
            event_id: created_event.id,
            calendar_id: calendar_id,
            summary: event_params[:summary]
          })

          {:ok, created_event}

        error ->
          error
      end
    else
      error -> error
    end
  end

  @doc """
  Create an event from a meeting proposal.
  """
  def create_event_from_proposal(user_id, proposal, event_params, opts \\ []) do
    base_params = %{
      start: proposal.start_time,
      end: proposal.end_time,
      summary: Map.get(event_params, :summary, "Meeting"),
      description: Map.get(event_params, :description, ""),
      location: Map.get(event_params, :location, nil),
      attendees: Map.get(event_params, :attendees, [])
    }

    # Add conference data if requested
    conference = Keyword.get(opts, :conference, true)
    create_opts = Keyword.put(opts, :conference, conference)

    create_event(user_id, base_params, create_opts)
  end

  @doc """
  Update an existing calendar event.
  """
  def update_event(user_id, event_id, event_params, opts \\ []) do
    calendar_id = Keyword.get(opts, :calendar_id, "primary")
    send_updates = Keyword.get(opts, :send_updates, "all")

    with {:ok, conn} <- Client.get_conn(user_id),
         :ok <- validate_event_params(event_params) do
      event_data = build_event_with_defaults(event_params)
      event_data = Map.put(event_data, :send_updates, send_updates)

      case Client.update_event(conn, calendar_id, event_id, event_data) do
        {:ok, updated_event} ->
          log_calendar_action(user_id, "event_updated", %{
            event_id: event_id,
            calendar_id: calendar_id,
            summary: event_params[:summary]
          })

          {:ok, updated_event}

        error ->
          error
      end
    else
      error -> error
    end
  end

  @doc """
  Delete a calendar event.
  """
  def delete_event(user_id, event_id, opts \\ []) do
    calendar_id = Keyword.get(opts, :calendar_id, "primary")
    send_updates = Keyword.get(opts, :send_updates, "all")

    with {:ok, conn} <- Client.get_conn(user_id) do
      case Client.delete_event(conn, calendar_id, event_id, send_updates: send_updates) do
        :ok ->
          log_calendar_action(user_id, "event_deleted", %{
            event_id: event_id,
            calendar_id: calendar_id
          })

          :ok

        error ->
          error
      end
    else
      error -> error
    end
  end

  @doc """
  Get a specific event by ID.
  """
  def get_event(user_id, event_id, opts \\ []) do
    calendar_id = Keyword.get(opts, :calendar_id, "primary")

    with {:ok, conn} <- Client.get_conn(user_id) do
      case GoogleApi.Calendar.V3.Api.Events.calendar_events_get(conn, calendar_id, event_id) do
        {:ok, event} -> {:ok, event}
        error -> error
      end
    else
      error -> error
    end
  end

  @doc """
  List events in a date range.
  """
  def list_events(user_id, start_date, end_date, opts \\ []) do
    calendar_id = Keyword.get(opts, :calendar_id, "primary")
    max_results = Keyword.get(opts, :max_results, 250)
    timezone = Keyword.get(opts, :timezone, "UTC")

    with {:ok, conn} <- Client.get_conn(user_id) do
      Client.list_events(conn, calendar_id,
        time_min: start_date,
        time_max: end_date,
        max_results: max_results,
        single_events: true,
        order_by: "startTime"
      )
    else
      error -> error
    end
  end

  @doc """
  Create a recurring event.
  """
  def create_recurring_event(user_id, event_params, recurrence_rules, opts \\ []) do
    # Add recurrence to event parameters
    event_with_recurrence = Map.put(event_params, :recurrence, recurrence_rules)

    create_event(user_id, event_with_recurrence, opts)
  end

  @doc """
  Respond to an event invitation.
  """
  def respond_to_invitation(user_id, event_id, response_status, opts \\ []) do
    calendar_id = Keyword.get(opts, :calendar_id, "primary")

    with {:ok, conn} <- Client.get_conn(user_id),
         {:ok, event} <- get_event(user_id, event_id, calendar_id: calendar_id) do
      # Find the user's attendee entry and update status
      user_email = get_user_email(user_id)

      updated_attendees =
        update_attendee_response(event.attendees || [], user_email, response_status)

      # Update the event with new attendee response
      update_params = %{attendees: updated_attendees}
      update_event(user_id, event_id, update_params, calendar_id: calendar_id)
    else
      error -> error
    end
  end

  @doc """
  Create a meeting with multiple attendees and send invitations.
  """
  def create_meeting_with_invitations(user_id, event_params, attendees, opts \\ []) do
    # Prepare attendee data
    attendee_data =
      Enum.map(attendees, fn attendee ->
        cond do
          is_binary(attendee) ->
            %{email: attendee, response_status: "needsAction"}

          is_map(attendee) ->
            %{
              email: Map.get(attendee, :email),
              display_name: Map.get(attendee, :display_name),
              response_status: Map.get(attendee, :response_status, "needsAction"),
              optional: Map.get(attendee, :optional, false)
            }

          true ->
            nil
        end
      end)
      |> Enum.filter(& &1)

    # Add attendees to event parameters
    event_with_attendees = Map.put(event_params, :attendees, attendee_data)

    # Add conference data if not explicitly disabled
    conference = Keyword.get(opts, :conference, true)
    create_opts = Keyword.put(opts, :conference, conference)

    create_event(user_id, event_with_attendees, create_opts)
  end

  @doc """
  Get events for a specific date.
  """
  def get_events_for_date(user_id, date, opts \\ []) do
    timezone = Keyword.get(opts, :timezone, "UTC")

    # Convert date to datetime range
    {:ok, start_dt} = DateTime.new(date, ~T[00:00:00], timezone)
    {:ok, end_dt} = DateTime.new(date, ~T[23:59:59], timezone)

    list_events(user_id, start_dt, end_dt, Keyword.put(opts, :timezone, timezone))
  end

  @doc """
  Get upcoming events for a user.
  """
  def get_upcoming_events(user_id, opts \\ []) do
    max_results = Keyword.get(opts, :max_results, 10)
    timezone = Keyword.get(opts, :timezone, "UTC")

    now = DateTime.now(timezone)
    # 30 days from now
    future_date = DateTime.add(now, 30 * 24 * 60 * 60, :second)

    list_events(user_id, now, future_date,
      max_results: max_results,
      timezone: timezone
    )
  end

  # Private functions

  defp build_event_with_defaults(params) do
    %{
      summary: Map.get(params, :summary, "Untitled Event"),
      description: Map.get(params, :description, ""),
      location: Map.get(params, :location, nil),
      start: Map.get(params, :start),
      end: Map.get(params, :end),
      attendees: Map.get(params, :attendees, []),
      visibility: Map.get(params, :visibility, @default_visibility),
      transparency: Map.get(params, :transparency, @default_transparency),
      guests_can_invite_others: Map.get(params, :guests_can_invite_others, true),
      guests_can_modify: Map.get(params, :guests_can_modify, false),
      guests_can_see_other_guests: Map.get(params, :guests_can_see_other_guests, true),
      reminders: Map.get(params, :reminders, @default_reminder_minutes),
      recurrence: Map.get(params, :recurrence, nil)
    }
    |> clean_nil_values()
  end

  defp validate_event_params(params) do
    cond do
      not Map.has_key?(params, :start) ->
        {:error, :missing_start_time}

      not Map.has_key?(params, :end) ->
        {:error, :missing_end_time}

      DateTime.compare(params.end, params.start) != :gt ->
        {:error, :end_time_before_start_time}

      # 4 hours max
      DateTime.diff(params.end, params.start, :second) > 4 * 60 * 60 ->
        {:error, :duration_too_long}

      true ->
        :ok
    end
  end

  defp get_user_email(user_id) do
    case Accounts.get_user(user_id) do
      {:ok, user} -> user.email
      {:error, _} -> nil
    end
  end

  defp update_attendee_response(attendees, user_email, response_status) do
    Enum.map(attendees, fn attendee ->
      if attendee.email == user_email do
        Map.put(attendee, :responseStatus, response_status)
      else
        attendee
      end
    end)
  end

  defp clean_nil_values(map) when is_map(map) do
    Enum.reduce(map, %{}, fn {key, value}, acc ->
      if value do
        case value do
          list when is_list(list) ->
            if Enum.empty?(list) do
              acc
            else
              Map.put(acc, key, value)
            end

          map when is_map(map) ->
            if map_size(map) == 0 do
              acc
            else
              Map.put(acc, key, value)
            end

          _ ->
            Map.put(acc, key, value)
        end
      else
        acc
      end
    end)
  end

  defp put_if(map, nil, _key, _value), do: map
  defp put_if(map, value, key, _value) when value == "", do: map
  defp put_if(map, _value, key, value), do: Map.put(map, key, value)

  defp log_calendar_action(user_id, action, metadata) do
    # This would integrate with the audit logging system
    Logger.info("Calendar action: #{action} by user #{user_id}", metadata: metadata)
  end
end
