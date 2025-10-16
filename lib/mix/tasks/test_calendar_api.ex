defmodule Mix.Tasks.TestCalendarApi do
  @moduledoc """
  Test Google Calendar API calls directly with user credentials.

  Usage:
    mix test_calendar_api
  """

  use Mix.Task
  require Logger

  alias Jump.{Repo, Accounts}
  alias Jump.Calendar.{Client, Events}

  @shortdoc "Test Google Calendar API calls"

  def run(_args) do
    # Start only what we need, not the full app
    {:ok, _} = Application.ensure_all_started(:postgrex)
    {:ok, _} = Application.ensure_all_started(:ecto)
    {:ok, _} = Application.ensure_all_started(:ecto_sql)
    {:ok, _} = Application.ensure_all_started(:hackney)
    {:ok, _} = Application.ensure_all_started(:tesla)

    # Start the repo
    {:ok, _} = Repo.start_link()

    IO.puts("\n=== Testing Google Calendar API ===\n")

    # Get user 1's credentials
    user_id = 1

    IO.puts("1. Fetching OAuth credentials for user #{user_id}...")

    case Accounts.get_oauth_account(user_id, :google) do
      {:ok, oauth} ->
        IO.puts("   ✓ Found OAuth account")
        IO.puts("   - Provider: #{oauth.provider}")
        IO.puts("   - Has access_token: #{!is_nil(oauth.access_token)}")
        IO.puts("   - Token expires: #{oauth.expires_at}")

        test_client_connection(oauth.access_token)
        test_list_events_direct(user_id)
        test_get_events_for_date(user_id)

      {:error, reason} ->
        IO.puts("   ✗ Failed to get OAuth account: #{inspect(reason)}")
    end

    IO.puts("\n=== Test Complete ===\n")
  end

  defp test_client_connection(access_token) do
    IO.puts("\n2. Testing Client.build_conn...")

    try do
      conn = Client.build_conn(access_token)
      IO.puts("   ✓ Connection created: #{inspect(conn.__struct__)}")
    rescue
      e ->
        IO.puts("   ✗ Error: #{Exception.message(e)}")
        IO.inspect(e, label: "   Exception")
    end
  end

  defp test_list_events_direct(user_id) do
    IO.puts("\n3. Testing Client.list_events (direct API call)...")

    try do
      case Client.get_conn(user_id) do
        {:ok, conn} ->
          IO.puts("   ✓ Got connection")

          # Try listing events for today
          today = Date.utc_today()
          {:ok, start_dt} = DateTime.new(today, ~T[00:00:00], "UTC")
          {:ok, end_dt} = DateTime.new(today, ~T[23:59:59], "UTC")

          IO.puts("   - Fetching events from #{start_dt} to #{end_dt}")

          case Client.list_events(conn, "primary",
                 time_min: start_dt,
                 time_max: end_dt,
                 max_results: 10,
                 single_events: true,
                 order_by: "startTime"
               ) do
            {:ok, response} ->
              IO.puts("   ✓ Got response!")
              IO.puts("   - Events count: #{length(response.events || [])}")
              IO.puts("   - Timezone: #{response.time_zone}")

              if response.events && length(response.events) > 0 do
                IO.puts("\n   First event:")
                event = List.first(response.events)
                IO.puts("     - ID: #{event.id}")
                IO.puts("     - Summary: #{event.summary}")
                IO.puts("     - Start: #{inspect(event.start)}")
                IO.puts("     - End: #{inspect(event.end)}")
              else
                IO.puts("   (No events found for today)")
              end

            {:error, reason} ->
              IO.puts("   ✗ API call failed: #{inspect(reason)}")
          end

        {:error, reason} ->
          IO.puts("   ✗ Failed to get connection: #{inspect(reason)}")
      end
    rescue
      e ->
        IO.puts("   ✗ Error: #{Exception.message(e)}")
        IO.puts("   Stack trace:")
        IO.puts(Exception.format_stacktrace(__STACKTRACE__))
    end
  end

  defp test_get_events_for_date(user_id) do
    IO.puts("\n4. Testing Events.get_events_for_date...")

    try do
      today = Date.utc_today()
      IO.puts("   - Date: #{today}")

      case Events.get_events_for_date(user_id, today, timezone: "UTC", max_results: 10) do
        {:ok, response} ->
          IO.puts("   ✓ Got response!")
          IO.puts("   - Events count: #{length(response.events || [])}")

        {:error, reason} ->
          IO.puts("   ✗ Failed: #{inspect(reason)}")
      end
    rescue
      e ->
        IO.puts("   ✗ Error: #{Exception.message(e)}")
        IO.puts("   Exception type: #{inspect(e.__struct__)}")
        IO.puts("   Stack trace:")
        IO.puts(Exception.format_stacktrace(__STACKTRACE__))
    end
  end
end
