defmodule Mix.Tasks.Test.Calendar do
  @moduledoc """
  Test Google Calendar API functions.

  Usage:
    mix test.calendar list                        # List today's events
    mix test.calendar list --date 2024-10-20      # List events for specific date
    mix test.calendar list --range 7              # List events for next 7 days
    mix test.calendar create "Meeting" --start "2024-10-20T14:00:00Z" --end "2024-10-20T15:00:00Z"
    mix test.calendar create "Team Sync" --start "2024-10-20T10:00:00Z" --end "2024-10-20T11:00:00Z" --attendees "user@example.com,other@example.com"
    mix test.calendar propose --date 2024-10-21 --duration 60  # Find available slots
  """

  use Mix.Task
  require Logger

  alias Jump.{Accounts, Calendar.Client, Calendar.Events, Repo}
  import Ecto.Query

  @shortdoc "Test Google Calendar API functions"

  def run(args) do
    # Ensure the application and all dependencies are started
    Application.ensure_all_started(:jump)

    case args do
      ["list" | opts] -> list_events(opts)
      ["create", summary | opts] -> create_event(summary, opts)
      ["propose" | opts] -> propose_times(opts)
      ["delete", event_id] -> delete_event(event_id)
      _ -> show_help()
    end
  end

  defp list_events(opts) do
    user_id = get_user_id_from_opts(opts)

    IO.puts("\nListing Calendar Events\n")

    {start_dt, end_dt, description} =
      cond do
        Enum.member?(opts, "--date") ->
          date_idx = Enum.find_index(opts, &(&1 == "--date"))
          date_str = Enum.at(opts, date_idx + 1)
          date = Date.from_iso8601!(date_str)
          start_dt = DateTime.new!(date, ~T[00:00:00], "Etc/UTC")
          end_dt = DateTime.new!(date, ~T[23:59:59], "Etc/UTC")
          {start_dt, end_dt, "Events for #{date}"}

        Enum.member?(opts, "--range") ->
          range_idx = Enum.find_index(opts, &(&1 == "--range"))
          days = Enum.at(opts, range_idx + 1) |> String.to_integer()
          start_dt = DateTime.utc_now()
          end_dt = DateTime.add(start_dt, days * 24 * 60 * 60, :second)
          {start_dt, end_dt, "Events for next #{days} days"}

        true ->
          date = Date.utc_today()
          start_dt = DateTime.new!(date, ~T[00:00:00], "Etc/UTC")
          end_dt = DateTime.new!(date, ~T[23:59:59], "Etc/UTC")
          {start_dt, end_dt, "Events for today (#{date})"}
      end

    IO.puts("#{description}\n")

    case Client.get_conn(user_id) do
      {:ok, conn} ->
        case Client.list_events(conn, "primary",
               time_min: start_dt,
               time_max: end_dt,
               max_results: 50,
               single_events: true,
               order_by: "startTime"
             ) do
          {:ok, response} ->
            if Enum.empty?(response.events || []) do
              IO.puts("  No events found")
            else
              Enum.each(response.events, fn event ->
                start_time = format_event_time(event.start)
                end_time = format_event_time(event.end)

                IO.puts("  - #{event.summary}")
                IO.puts("    Time: #{start_time} → #{end_time}")
                if event.location, do: IO.puts("    Location: #{event.location}")
                if event.attendees, do: IO.puts("    Attendees: #{length(event.attendees)}")
                IO.puts("    ID: #{event.id}")
                IO.puts("")
              end)

              IO.puts("Total: #{length(response.events)} events")
            end

          {:error, reason} ->
            IO.puts("Failed: #{inspect(reason)}")
        end

      {:error, reason} ->
        IO.puts("No OAuth connection: #{inspect(reason)}")
    end
  end

  defp create_event(summary, opts) do
    user_id = get_user_id_from_opts(opts)

    start_idx = Enum.find_index(opts, &(&1 == "--start"))
    end_idx = Enum.find_index(opts, &(&1 == "--end"))

    unless start_idx && end_idx do
      IO.puts("--start and --end are required")
      :ok
    else
      start_str = Enum.at(opts, start_idx + 1)
      end_str = Enum.at(opts, end_idx + 1)

      {:ok, start_dt, _} = DateTime.from_iso8601(start_str)
      {:ok, end_dt, _} = DateTime.from_iso8601(end_str)

      attendees =
        if Enum.member?(opts, "--attendees") do
          att_idx = Enum.find_index(opts, &(&1 == "--attendees"))
          Enum.at(opts, att_idx + 1) |> String.split(",")
          []
        end

      location =
        if Enum.member?(opts, "--location") do
          loc_idx = Enum.find_index(opts, &(&1 == "--location"))
          Enum.at(opts, loc_idx + 1)
        end

      IO.puts("\nCreating Calendar Event\n")
      IO.puts("  Summary: #{summary}")
      IO.puts("  Start: #{start_dt}")
      IO.puts("  End: #{end_dt}")
      if !Enum.empty?(attendees), do: IO.puts("  Attendees: #{Enum.join(attendees, ", ")}")
      if location, do: IO.puts("  Location: #{location}")
      IO.puts("")

      event_params = %{
        start: start_dt,
        end: end_dt,
        summary: summary,
        location: location,
        attendees: attendees
      }

      case Events.create_event(user_id, event_params) do
        {:ok, event} ->
          IO.puts("Event created successfully!")
          IO.puts("  ID: #{event.id}")
          IO.puts("  Link: #{event.htmlLink}")

        {:error, reason} ->
          IO.puts("❌ Failed: #{inspect(reason)}")
      end
    end
  end

  defp propose_times(opts) do
    user_id = get_user_id_from_opts(opts)

    date =
      if Enum.member?(opts, "--date") do
        date_idx = Enum.find_index(opts, &(&1 == "--date"))
        Date.from_iso8601!(Enum.at(opts, date_idx + 1))
      else
        Date.utc_today()
      end

    duration =
      if Enum.member?(opts, "--duration") do
        dur_idx = Enum.find_index(opts, &(&1 == "--duration"))
        String.to_integer(Enum.at(opts, dur_idx + 1))
      else
        60
      end

    window_start = DateTime.new!(date, ~T[09:00:00], "Etc/UTC")
    window_end = DateTime.new!(date, ~T[17:00:00], "Etc/UTC")

    IO.puts("\n🔍 Finding Available Time Slots\n")
    IO.puts("  Date: #{date}")
    IO.puts("  Duration: #{duration} minutes")
    IO.puts("  Window: 9 AM - 5 PM UTC\n")

    case Jump.Calendar.Proposals.get_proposals(
           user_id,
           window_start,
           window_end,
           duration,
           "UTC",
           5,
           []
         ) do
      proposals when is_list(proposals) ->
        if Enum.empty?(proposals) do
          IO.puts("  No available slots found")
        else
          Enum.each(proposals, fn proposal ->
            IO.puts("  - #{proposal.start_time} -> #{proposal.end_time}")
            IO.puts("    (#{proposal.duration_minutes} minutes)")
          end)
        end

      {:error, reason} ->
        IO.puts("❌ Failed: #{inspect(reason)}")
    end
  end

  defp delete_event(event_id) do
    user_id = get_user_id_from_opts([])

    IO.puts("\n🗑️  Deleting Event: #{event_id}\n")

    case Events.delete_event(user_id, event_id) do
      :ok ->
        IO.puts("Event deleted successfully!")

      {:error, reason} ->
        IO.puts("❌ Failed: #{inspect(reason)}")
    end
  end

  defp get_user_id_from_opts(opts) do
    if Enum.member?(opts, "--user-id") do
      idx = Enum.find_index(opts, &(&1 == "--user-id"))
      Enum.at(opts, idx + 1) |> String.to_integer()
    else
      case Repo.one(from u in Accounts.User, select: u.id, limit: 1) do
        nil ->
          IO.puts("No users found in database. Please sign up first.")
          System.halt(1)

        id ->
          IO.puts("Using User ID: #{id}")
          id
      end
    end
  end

  # Handle EventDateTime structs from Google API (atom keys)
  defp format_event_time(%{dateTime: dt}) when not is_nil(dt), do: DateTime.to_iso8601(dt)
  defp format_event_time(%{date: d}) when not is_nil(d), do: Date.to_iso8601(d)
  defp format_event_time(nil), do: "N/A"
  defp format_event_time(_), do: "N/A"

  defp show_help do
    IO.puts("""

    Google Calendar Test Commands

    List events:
      mix test.calendar list                        # Today's events
      mix test.calendar list --date 2024-10-20      # Specific date
      mix test.calendar list --range 7              # Next 7 days

    Create event:
      mix test.calendar create "Meeting Title" \\
        --start "2024-10-20T14:00:00Z" \\
        --end "2024-10-20T15:00:00Z" \\
        --attendees "user@example.com,other@example.com" \\
        --location "Conference Room A"

    Propose times:
      mix test.calendar propose --date 2024-10-21 --duration 60

    Delete event:
      mix test.calendar delete <event_id>

    """)
  end
end
