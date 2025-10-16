defmodule Jump.Mocks.GoogleAPIMock do
  @moduledoc """
  Mock Google API responses for Gmail and Calendar APIs.
  """

  @doc """
  Mock a successful Gmail message list response
  """
  def mock_gmail_messages_list(count \\ 5) do
    messages =
      1..count
      |> Enum.map(fn i ->
        %{
          "id" => "message_#{i}",
          "threadId" => "thread_1",
          "labelIds" => ["INBOX"],
          "snippet" => "Test message #{i}"
        }
      end)

    {:ok, %{"messages" => messages, "resultSizeEstimate" => count}}
  end

  @doc """
  Mock a successful Gmail message get response
  """
  def mock_gmail_message_get(message_id \\ "message_1") do
    {:ok,
     %{
       "id" => message_id,
       "threadId" => "thread_1",
       "labelIds" => ["INBOX"],
       "payload" => %{
         "mimeType" => "text/plain",
         "headers" => [
           %{"name" => "From", "value" => "sender@example.com"},
           %{"name" => "To", "value" => "recipient@example.com"},
           %{"name" => "Subject", "value" => "Test Subject"}
         ],
         "body" => %{"data" => Base.encode64("Test message body")}
       },
       "sizeEstimate" => 1000
     }}
  end

  @doc """
  Mock a successful Gmail send message response
  """
  def mock_gmail_message_send(message_id \\ "sent_message_1") do
    {:ok,
     %{
       "id" => message_id,
       "threadId" => "thread_new",
       "labelIds" => ["SENT"],
       "sizeEstimate" => 1000
     }}
  end

  @doc """
  Mock a Gmail API error
  """
  def mock_gmail_error(error_msg \\ "Invalid message") do
    {:error, %{"error" => %{"message" => error_msg, "code" => 400}}}
  end

  @doc """
  Mock a successful Calendar list response
  """
  def mock_calendar_list do
    {:ok,
     %{
       "items" => [
         %{
           "id" => "primary",
           "summary" => "Primary Calendar",
           "primary" => true,
           "timeZone" => "UTC"
         },
         %{
           "id" => "secondary",
           "summary" => "Secondary Calendar",
           "primary" => false,
           "timeZone" => "America/New_York"
         }
       ]
     }}
  end

  @doc """
  Mock a successful Calendar event list response
  """
  def mock_calendar_events_list(count \\ 3) do
    events =
      1..count
      |> Enum.map(fn i ->
        %{
          "id" => "event_#{i}",
          "summary" => "Test Event #{i}",
          "description" => "Test event description #{i}",
          "start" => %{"dateTime" => "2024-01-20T10:00:00Z"},
          "end" => %{"dateTime" => "2024-01-20T11:00:00Z"},
          "attendees" => [
            %{"email" => "attendee#{i}@example.com", "responseStatus" => "accepted"}
          ]
        }
      end)

    {:ok, %{"items" => events}}
  end

  @doc """
  Mock a successful Calendar event create response
  """
  def mock_calendar_event_create(event_id \\ "event_new") do
    {:ok,
     %{
       "id" => event_id,
       "summary" => "New Event",
       "description" => "New event created",
       "start" => %{"dateTime" => "2024-01-20T14:00:00Z"},
       "end" => %{"dateTime" => "2024-01-20T15:00:00Z"},
       "conferenceData" => %{
         "entryPoints" => [
           %{
             "entryPointType" => "video",
             "uri" => "https://meet.google.com/abc-defg-hij"
           }
         ]
       },
       "htmlLink" => "https://calendar.google.com/calendar/event?eid=event_new"
     }}
  end

  @doc """
  Mock a successful freebusy query response
  """
  def mock_freebusy_query do
    {:ok,
     %{
       "calendars" => %{
         "primary" => %{
           "busy" => [
             %{
               "start" => "2024-01-20T09:00:00Z",
               "end" => "2024-01-20T10:00:00Z"
             },
             %{
               "start" => "2024-01-20T14:00:00Z",
               "end" => "2024-01-20T15:00:00Z"
             }
           ]
         }
       }
     }}
  end

  @doc """
  Mock a Calendar API error
  """
  def mock_calendar_error(error_msg \\ "Calendar not found") do
    {:error, %{"error" => %{"message" => error_msg, "code" => 404}}}
  end
end
