defmodule Jump.Agent.Tools do
  @moduledoc """
  LangChain tool functions for the AI agent.
  """

  alias Jump.{Gmail, Calendar, CRM, RAG}
  alias LangChain.Function
  alias LangChain.Message
  require Logger

  @doc """
  Get all available tools for the agent.
  """
  def all() do
    [
      create_send_email_tool(),
      create_propose_times_tool(),
      create_create_event_tool(),
      create_list_calendar_events_tool(),
      create_find_contact_tool(),
      create_add_note_tool(),
      create_search_rag_tool()
    ]
  end

  # Gmail Send Email Tool
  defp create_send_email_tool() do
    Function.new!(%{
      name: "send_email_via_gmail",
      description: "Send an email as the authenticated user with proper threading support.",
      parameters_schema: %{
        type: "object",
        properties: %{
          to: %{
            type: "array",
            items: %{type: "string", format: "email"},
            description: "List of recipient email addresses"
          },
          subject: %{
            type: "string",
            description: "Email subject line"
          },
          html_body: %{
            type: "string",
            description: "HTML content of the email"
          },
          text_body: %{
            type: "string",
            description: "Plain text content of the email"
          },
          reply_to_message_id: %{
            type: "string",
            description: "Gmail message ID to reply to (for threading)"
          },
          references: %{
            type: "array",
            items: %{type: "string"},
            description: "List of message IDs for threading references"
          }
        },
        required: ["to", "subject", "html_body"]
      },
      function: fn args, context ->
        user_id = Map.get(context, :user_id)

        case execute_send_email(args, user_id) do
          {:ok, result} -> {:ok, Jason.encode!(result)}
          {:error, reason} -> {:error, reason}
        end
      end
    })
  end

  defp execute_send_email(args, user_id) do
    try do
      result =
        Gmail.Composer.send_email(
          user_id,
          args["to"],
          args["subject"],
          args["html_body"],
          Map.get(args, "text_body"),
          Map.get(args, "reply_to_message_id"),
          Map.get(args, "references", [])
        )

      case result do
        {:ok, message_id} ->
          {:ok,
           %{
             "message_id" => message_id,
             "status" => "sent",
             "recipients" => args["to"],
             "subject" => args["subject"]
           }}

        {:error, reason} ->
          {:error, "Failed to send email: #{inspect(reason)}"}
      end
    rescue
      e ->
        Logger.error("Email sending error: #{inspect(e)}")
        {:error, "Email sending failed: #{Exception.message(e)}"}
    end
  end

  # Calendar Propose Times Tool
  defp create_propose_times_tool() do
    Function.new!(%{
      name: "propose_calendar_times",
      description: "Get available meeting time slots in the user's timezone.",
      parameters_schema: %{
        type: "object",
        properties: %{
          duration_minutes: %{
            type: "integer",
            description: "Meeting duration in minutes",
            minimum: 15,
            maximum: 480
          },
          window_start: %{
            type: "string",
            format: "date-time",
            description: "Start of the time window to search for availability"
          },
          window_end: %{
            type: "string",
            format: "date-time",
            description: "End of the time window to search for availability"
          },
          min_slots: %{
            type: "integer",
            description: "Minimum number of time slots to return",
            minimum: 1,
            maximum: 10
          },
          attendees: %{
            type: "array",
            items: %{type: "string", format: "email"},
            description: "List of attendee email addresses to check availability for"
          },
          timezone: %{
            type: "string",
            description: "Timezone for the meeting (e.g., 'America/New_York')"
          }
        },
        required: ["duration_minutes", "window_start", "window_end", "timezone"]
      },
      function: fn args, context ->
        user_id = Map.get(context, :user_id)

        case execute_propose_times(args, user_id) do
          {:ok, result} -> {:ok, Jason.encode!(result)}
          {:error, reason} -> {:error, reason}
        end
      end
    })
  end

  defp execute_propose_times(args, user_id) do
    try do
      # Parse datetime strings
      window_start =
        case DateTime.from_iso8601(args["window_start"]) do
          {:ok, datetime, _offset} -> datetime
          {:error, reason} -> raise ArgumentError, inspect(reason)
        end

      window_end =
        case DateTime.from_iso8601(args["window_end"]) do
          {:ok, datetime, _offset} -> datetime
          {:error, reason} -> raise ArgumentError, inspect(reason)
        end

      duration = args["duration_minutes"]
      timezone = args["timezone"]
      min_slots = Map.get(args, "min_slots", 3)
      attendees = Map.get(args, "attendees", [])

      # Get proposals
      proposals =
        Calendar.Proposals.get_proposals(
          user_id,
          window_start,
          window_end,
          duration,
          timezone,
          min_slots,
          attendees
        )

      {:ok,
       %{
         "proposals" => proposals,
         "duration_minutes" => duration,
         "timezone" => timezone,
         "attendees" => attendees
       }}
    rescue
      e ->
        Logger.error("Calendar proposal error: #{inspect(e)}")
        {:error, "Failed to get calendar proposals: #{Exception.message(e)}"}
    end
  end

  # Calendar List Events Tool
  defp create_list_calendar_events_tool() do
    Function.new!(%{
      name: "list_calendar_events",
      description:
        "Get calendar events directly from Google Calendar. Use this to fetch today's events, events in a date range, or upcoming events. This provides real-time calendar data.",
      parameters_schema: %{
        type: "object",
        properties: %{
          date: %{
            type: "string",
            format: "date",
            description:
              "Get events for a specific date (YYYY-MM-DD). Mutually exclusive with start_date/end_date."
          },
          start_date: %{
            type: "string",
            format: "date-time",
            description: "Start of date range (ISO8601). Use with end_date."
          },
          end_date: %{
            type: "string",
            format: "date-time",
            description: "End of date range (ISO8601). Use with start_date."
          },
          timezone: %{
            type: "string",
            description: "Timezone (e.g., 'America/New_York'). Defaults to UTC."
          },
          calendar_id: %{
            type: "string",
            description: "Calendar ID (defaults to 'primary')"
          },
          max_results: %{
            type: "integer",
            description: "Maximum events to return (default: 50)",
            minimum: 1,
            maximum: 250
          }
        }
      },
      function: fn args, context ->
        user_id = Map.get(context, :user_id)

        case execute_list_calendar_events(args, user_id) do
          {:ok, result} -> {:ok, Jason.encode!(result)}
          {:error, reason} -> {:error, reason}
        end
      end
    })
  end

  defp execute_list_calendar_events(args, user_id) do
    try do
      timezone = Map.get(args, "timezone", "UTC")
      calendar_id = Map.get(args, "calendar_id", "primary")
      max_results = Map.get(args, "max_results", 50)

      result =
        cond do
          # Case 1: Specific date
          Map.has_key?(args, "date") ->
            date = Date.from_iso8601!(args["date"])

            Calendar.Events.get_events_for_date(user_id, date,
              timezone: timezone,
              calendar_id: calendar_id,
              max_results: max_results
            )

          # Case 2: Date range
          Map.has_key?(args, "start_date") && Map.has_key?(args, "end_date") ->
            # Parse datetime strings, adding timezone if missing
            start_dt = parse_datetime_with_fallback(args["start_date"], timezone)
            end_dt = parse_datetime_with_fallback(args["end_date"], timezone)

            Calendar.Events.list_events(user_id, start_dt, end_dt,
              timezone: timezone,
              calendar_id: calendar_id,
              max_results: max_results
            )

          # Case 3: Default to today
          true ->
            today = Date.utc_today()

            Calendar.Events.get_events_for_date(user_id, today,
              timezone: timezone,
              calendar_id: calendar_id,
              max_results: max_results
            )
        end

      case result do
        {:ok, %{events: events}} ->
          formatted_events = format_events_for_response(events)

          {:ok,
           %{
             "success" => true,
             "events" => formatted_events,
             "count" => length(events),
             "timezone" => timezone
           }}

        {:error, reason} ->
          {:error, "Failed to fetch calendar events: #{inspect(reason)}"}
      end
    rescue
      e ->
        Logger.error("Calendar events fetch error: #{inspect(e)}")
        {:error, "Failed to fetch calendar events: #{Exception.message(e)}"}
    end
  end

  defp format_events_for_response(events) do
    Enum.map(events, fn event ->
      %{
        "id" => event.id,
        "summary" => event.summary,
        "start" => format_event_time(event.start),
        "end" => format_event_time(event.end),
        "description" => event.description,
        "location" => event.location,
        "attendees" => format_attendees(event.attendees),
        "status" => event.status,
        "html_link" => event.htmlLink
      }
    end)
  end

  # Handle EventDateTime structs from Google API (atom keys)
  defp format_event_time(%{dateTime: dt}) when not is_nil(dt), do: DateTime.to_iso8601(dt)
  defp format_event_time(%{date: d}) when not is_nil(d), do: Date.to_iso8601(d)
  defp format_event_time(nil), do: nil
  defp format_event_time(_), do: "N/A"

  defp format_attendees(nil), do: []

  defp format_attendees(attendees) when is_list(attendees) do
    Enum.map(attendees, fn att ->
      %{
        "email" => att.email,
        "name" => att.displayName,
        "status" => att.responseStatus
      }
    end)
  end

  # Helper to parse datetime strings, handling missing timezone offsets
  defp parse_datetime_with_fallback(datetime_string, timezone \\ "UTC") do
    case DateTime.from_iso8601(datetime_string) do
      {:ok, dt, _offset} ->
        dt

      {:error, :missing_offset} ->
        # If timezone offset is missing, add it and try again
        datetime_with_offset = datetime_string <> "Z"

        case DateTime.from_iso8601(datetime_with_offset) do
          {:ok, dt, _} -> dt
          {:error, _} -> raise ArgumentError, "Invalid datetime format: #{datetime_string}"
        end

      {:error, reason} ->
        raise ArgumentError, "Failed to parse datetime '#{datetime_string}': #{inspect(reason)}"
    end
  end

  # Calendar Create Event Tool
  defp create_create_event_tool() do
    Function.new!(%{
      name: "create_calendar_event",
      description: "Create a Google Calendar event.",
      parameters_schema: %{
        type: "object",
        properties: %{
          start: %{
            type: "string",
            format: "date-time",
            description: "Event start time"
          },
          end: %{
            type: "string",
            format: "date-time",
            description: "Event end time"
          },
          summary: %{
            type: "string",
            description: "Event title/summary"
          },
          attendees: %{
            type: "array",
            items: %{type: "string", format: "email"},
            description: "List of attendee email addresses"
          },
          description: %{
            type: "string",
            description: "Event description"
          },
          location: %{
            type: "string",
            description: "Event location"
          },
          conference: %{
            type: "boolean",
            description: "Whether to create a Google Meet conference"
          }
        },
        required: ["start", "end", "summary"]
      },
      function: fn args, context ->
        user_id = Map.get(context, :user_id)

        case execute_create_event(args, user_id) do
          {:ok, result} -> {:ok, Jason.encode!(result)}
          {:error, reason} -> {:error, reason}
        end
      end
    })
  end

  defp execute_create_event(args, user_id) do
    try do
      start_time =
        case DateTime.from_iso8601(args["start"]) do
          {:ok, datetime, _offset} -> datetime
          {:error, reason} -> raise ArgumentError, inspect(reason)
        end

      end_time =
        case DateTime.from_iso8601(args["end"]) do
          {:ok, datetime, _offset} -> datetime
          {:error, reason} -> raise ArgumentError, inspect(reason)
        end

      summary = args["summary"]
      attendees = Map.get(args, "attendees", [])
      description = Map.get(args, "description", "")
      location = Map.get(args, "location")
      conference = Map.get(args, "conference", false)

      result =
        Calendar.Events.create_event(
          user_id,
          start_time,
          end_time,
          summary,
          attendees,
          description,
          location,
          conference
        )

      case result do
        {:ok, event} ->
          {:ok,
           %{
             "event_id" => event.id,
             "summary" => event.summary,
             "start" => event.start,
             "end" => event.end,
             "attendees" => attendees,
             "conference_link" => get_conference_link(event),
             "status" => "created"
           }}

        {:error, reason} ->
          {:error, "Failed to create event: #{inspect(reason)}"}
      end
    rescue
      e ->
        Logger.error("Calendar event creation error: #{inspect(e)}")
        {:error, "Failed to create calendar event: #{Exception.message(e)}"}
    end
  end

  # HubSpot Find/Create Contact Tool
  defp create_find_contact_tool() do
    Function.new!(%{
      name: "hubspot_find_or_create_contact",
      description: "Find or create a HubSpot contact by email address.",
      parameters_schema: %{
        type: "object",
        properties: %{
          email: %{
            type: "string",
            format: "email",
            description: "Contact email address"
          },
          name: %{
            type: "string",
            description: "Contact full name"
          },
          properties: %{
            type: "object",
            description: "Additional contact properties as key-value pairs"
          }
        },
        required: ["email"]
      },
      function: fn args, context ->
        user_id = Map.get(context, :user_id)

        case execute_find_contact(args, user_id) do
          {:ok, result} -> {:ok, Jason.encode!(result)}
          {:error, reason} -> {:error, reason}
        end
      end
    })
  end

  defp execute_find_contact(args, user_id) do
    try do
      email = args["email"]
      name = Map.get(args, "name")
      properties = Map.get(args, "properties", %{})

      result = CRM.HubSpot.Client.get_or_create_contact(email, name, properties)

      case result do
        {:ok, contact} ->
          {:ok,
           %{
             "contact_id" => contact.id,
             "email" => contact.email,
             "name" => contact.name,
             "properties" => contact.properties,
             "status" => "found_or_created"
           }}

        {:error, reason} ->
          {:error, "Failed to find/create contact: #{inspect(reason)}"}
      end
    rescue
      e ->
        Logger.error("HubSpot contact error: #{inspect(e)}")
        {:error, "Failed to manage HubSpot contact: #{Exception.message(e)}"}
    end
  end

  # HubSpot Add Note Tool
  defp create_add_note_tool() do
    Function.new!(%{
      name: "hubspot_add_note",
      description: "Add a note to a HubSpot contact.",
      parameters_schema: %{
        type: "object",
        properties: %{
          contact_id: %{
            type: "string",
            description: "HubSpot contact ID"
          },
          text: %{
            type: "string",
            description: "Note content"
          },
          timestamp: %{
            type: "string",
            format: "date-time",
            description: "Note timestamp (defaults to current time)"
          }
        },
        required: ["contact_id", "text"]
      },
      function: fn args, _context ->
        case execute_add_note(args, nil) do
          {:ok, result} -> {:ok, Jason.encode!(result)}
          {:error, reason} -> {:error, reason}
        end
      end
    })
  end

  defp execute_add_note(args, _user_id) do
    try do
      contact_id = args["contact_id"]
      text = args["text"]

      timestamp =
        case Map.get(args, "timestamp") do
          nil ->
            DateTime.utc_now()

          ts ->
            case DateTime.from_iso8601(ts) do
              {:ok, datetime, _offset} -> datetime
              {:error, reason} -> raise ArgumentError, inspect(reason)
            end
        end

      result = CRM.HubSpot.Client.create_contact_note(contact_id, text, timestamp)

      case result do
        {:ok, note} ->
          {:ok,
           %{
             "note_id" => note.id,
             "contact_id" => contact_id,
             "text" => text,
             "timestamp" => DateTime.to_iso8601(timestamp),
             "status" => "created"
           }}

        {:error, reason} ->
          {:error, "Failed to add note: #{inspect(reason)}"}
      end
    rescue
      e ->
        Logger.error("HubSpot note creation error: #{inspect(e)}")
        {:error, "Failed to create HubSpot note: #{Exception.message(e)}"}
    end
  end

  # RAG Search Tool (enhanced version of the existing one)
  defp create_search_rag_tool() do
    Function.new!(%{
      name: "search_rag",
      description:
        "Search through emails, calendar events, and contacts to find relevant information. Use this to answer questions about past communications, people mentioned, topics discussed, or meeting details.",
      parameters_schema: %{
        type: "object",
        properties: %{
          query: %{
            type: "string",
            description: "The search query to find relevant information"
          },
          search_type: %{
            type: "string",
            description: "Type of search: general, person, temporal, contact, scheduling",
            enum: ["general", "person", "temporal", "contact", "scheduling"]
          },
          max_results: %{
            type: "integer",
            description: "Maximum number of results to return (default: 10)",
            minimum: 1,
            maximum: 20
          },
          time_range: %{
            type: "string",
            description: "Time range for search: recent, this_week, this_month, this_year",
            enum: ["recent", "this_week", "this_month", "this_year"]
          }
        },
        required: ["query"]
      },
      function: fn args, context ->
        user_id = Map.get(context, :user_id)

        case execute_search_rag(args, user_id) do
          {:ok, result} -> {:ok, Jason.encode!(result)}
          {:error, reason} -> {:error, reason}
        end
      end
    })
  end

  defp execute_search_rag(args, user_id) do
    query = args["query"]
    search_type = Map.get(args, "search_type", "general")
    max_results = Map.get(args, "max_results", 10)
    time_range = Map.get(args, "time_range", "recent")

    try do
      # Use the existing RAG search
      case RAG.Retriever.search_and_retrieve(
             user_id,
             query,
             search_type,
             max_results,
             time_range
           ) do
        {:ok, results} ->
          # Build answer with citations
          answer =
            RAG.AnswerBuilder.build_answer(
              query,
              results,
              style: :comprehensive,
              include_citations: true
            )

          {:ok,
           %{
             "query" => query,
             "search_type" => search_type,
             "results_count" => length(results),
             "answer" => answer.answer,
             "style" => to_string(answer.style),
             "confidence" => answer.confidence,
             "sources" => answer.sources
           }}

        {:error, reason} ->
          {:error, "Search failed: #{inspect(reason)}"}
      end
    rescue
      e ->
        Logger.error("RAG search failed!",
          user_id: user_id,
          query: query,
          search_type: search_type,
          error: Exception.message(e),
          error_type: e.__struct__,
          stacktrace: Exception.format_stacktrace(__STACKTRACE__)
        )

        {:error, "Search failed: #{Exception.message(e)}"}
    end
  end

  defp get_conference_link(event) do
    # Extract conference link from event if available
    case event.conference_data do
      %{"entryPoints" => entry_points} ->
        entry_point = Enum.find(entry_points, &(&1["entryPointType"] == "video"))
        entry_point && entry_point["uri"]

      _ ->
        nil
    end
  end
end
