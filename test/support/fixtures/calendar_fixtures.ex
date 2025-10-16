defmodule Jump.CalendarFixtures do
  @moduledoc """
  Fixtures for Calendar-related tests.
  """

  @doc """
  Generate a calendar event fixture
  """
  def calendar_event_fixture(attrs \\ %{}) do
    start_dt = Map.get(attrs, :start, DateTime.utc_now())
    end_dt = Map.get(attrs, :end, DateTime.add(start_dt, 3600))

    attrs =
      Enum.into(attrs, %{
        "id" => "event_#{:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)}",
        "summary" => "Test Event",
        "description" => "Test event description",
        "start" => %{"dateTime" => DateTime.to_iso8601(start_dt)},
        "end" => %{"dateTime" => DateTime.to_iso8601(end_dt)},
        "organizer" => %{
          "email" => "organizer@example.com",
          "displayName" => "Test Organizer"
        },
        "attendees" => [
          %{
            "email" => "attendee1@example.com",
            "displayName" => "Attendee 1",
            "responseStatus" => "accepted"
          }
        ],
        "location" => "Test Location",
        "conferenceData" => %{
          "entryPoints" => [
            %{
              "entryPointType" => "video",
              "uri" => "https://meet.google.com/test-meeting"
            }
          ]
        }
      })

    %{
      "id" => attrs["id"],
      "summary" => attrs["summary"],
      "description" => attrs["description"],
      "start" => attrs["start"],
      "end" => attrs["end"],
      "organizer" => attrs["organizer"],
      "attendees" => attrs["attendees"],
      "location" => attrs["location"],
      "conferenceData" => attrs["conferenceData"]
    }
  end

  @doc """
  Generate a calendar list fixture
  """
  def calendar_list_fixture(attrs \\ %{}) do
    attrs =
      Enum.into(attrs, %{
        "id" => "primary",
        "summary" => "Primary Calendar",
        "primary" => true,
        "timeZone" => "UTC",
        "description" => "Primary calendar",
        "backgroundColor" => "#3366CC"
      })

    %{
      "id" => attrs["id"],
      "summary" => attrs["summary"],
      "primary" => attrs["primary"],
      "timeZone" => attrs["timeZone"],
      "description" => attrs["description"],
      "backgroundColor" => attrs["backgroundColor"]
    }
  end

  @doc """
  Generate a free/busy block fixture
  """
  def freebusy_block_fixture(attrs \\ %{}) do
    now = DateTime.utc_now()
    start_time = Map.get(attrs, :start, DateTime.add(now, 3600))
    end_time = Map.get(attrs, :end, DateTime.add(start_time, 1800))

    %{
      "start" => DateTime.to_iso8601(start_time),
      "end" => DateTime.to_iso8601(end_time)
    }
  end

  @doc """
  Generate a freebusy query response fixture
  """
  def freebusy_response_fixture(calendar_id \\ "primary") do
    {:ok,
     %{
       "calendars" => %{
         calendar_id => %{
           "busy" => [
             freebusy_block_fixture(
               start: DateTime.add(DateTime.utc_now(), 3600),
               end: DateTime.add(DateTime.utc_now(), 5400)
             )
           ]
         }
       }
     }}
  end

  @doc """
  Generate a time slot fixture (for availability checking)
  """
  def time_slot_fixture(attrs \\ %{}) do
    start_dt = Map.get(attrs, :start, DateTime.utc_now())
    end_dt = Map.get(attrs, :end, DateTime.add(start_dt, 1800))

    %{
      "start_time" => start_dt,
      "end_time" => end_dt,
      "duration_minutes" => div(DateTime.diff(end_dt, start_dt), 60),
      "score" => Map.get(attrs, :score, 0.9)
    }
  end

  @doc """
  Generate a meeting proposal fixture
  """
  def meeting_proposal_fixture(attrs \\ %{}) do
    start_dt = Map.get(attrs, :start, DateTime.add(DateTime.utc_now(), 86400))
    end_dt = Map.get(attrs, :end, DateTime.add(start_dt, 1800))

    %{
      "id" => "prop_#{:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)}",
      "start_time" => start_dt,
      "end_time" => end_dt,
      "duration_minutes" => 30,
      "score" => 0.95,
      "reason" => "Good availability for all participants",
      "timezone" => "UTC",
      "day_of_week" => Date.day_of_week(DateTime.to_date(start_dt))
    }
  end
end
