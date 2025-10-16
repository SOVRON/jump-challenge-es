defmodule Jump.RAG.Tools do
  @moduledoc """
  LangChain tool integration for RAG search and retrieval capabilities.
  """

  alias Jump.RAG.{Search, Retriever, AnswerBuilder}
  alias Jump.TimeHelpers
  alias LangChain.Function
  alias LangChain.Message
  require Logger

  @doc """
  Create RAG search tool for LangChain integration.
  """
  def create_rag_search_tool() do
    %Function{
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
      }
    }
  end

  @doc """
  Create tool for finding people and contact information.
  """
  def create_find_people_tool() do
    %Function{
      name: "find_people",
      description:
        "Search for specific people, their contact information, and related communications. Use this when asked about who someone is, how to contact them, or what interactions you've had with them.",
      parameters_schema: %{
        type: "object",
        properties: %{
          person_identifier: %{
            type: "string",
            description: "Name, email address, or identifier of the person to find"
          },
          include_communications: %{
            type: "boolean",
            description:
              "Whether to include recent communications with this person (default: true)"
          },
          max_communications: %{
            type: "integer",
            description: "Maximum number of recent communications to include (default: 5)",
            minimum: 1,
            maximum: 10
          }
        },
        required: ["person_identifier"]
      }
    }
  end

  @doc """
  Create tool for searching emails and messages.
  """
  def create_search_emails_tool() do
    %Function{
      name: "search_emails",
      description:
        "Search through email messages for specific topics, people, or time periods. Use this to find what was discussed in emails, who said what, or when conversations happened.",
      parameters_schema: %{
        type: "object",
        properties: %{
          query: %{
            type: "string",
            description: "Search terms to find in email messages"
          },
          sender: %{
            type: "string",
            description: "Filter by sender email or name"
          },
          recipient: %{
            type: "string",
            description: "Filter by recipient email or name"
          },
          date_range: %{
            type: "string",
            description: "Time range: last_week, last_month, last_quarter, custom",
            enum: ["last_week", "last_month", "last_quarter", "custom"]
          },
          custom_start_date: %{
            type: "string",
            description:
              "Custom start date in YYYY-MM-DD format (required if date_range is 'custom')"
          },
          custom_end_date: %{
            type: "string",
            description:
              "Custom end date in YYYY-MM-DD format (required if date_range is 'custom')"
          },
          max_results: %{
            type: "integer",
            description: "Maximum number of email results (default: 10)",
            minimum: 1,
            maximum: 20
          }
        },
        required: ["query"]
      }
    }
  end

  @doc """
  Create tool for searching calendar events and scheduling information.
  """
  def create_search_calendar_tool() do
    %Function{
      name: "search_calendar",
      description:
        "Search through calendar events, meetings, and scheduling information. Use this to find when meetings happened, who attended, what was discussed, or scheduling patterns.",
      parameters_schema: %{
        type: "object",
        properties: %{
          query: %{
            type: "string",
            description: "Search terms to find in calendar events"
          },
          attendees: %{
            type: "array",
            items: %{type: "string"},
            description: "Filter by specific attendees (emails or names)"
          },
          date_range: %{
            type: "string",
            description: "Time range: this_week, this_month, this_year, custom",
            enum: ["this_week", "this_month", "this_year", "custom"]
          },
          custom_start_date: %{
            type: "string",
            description: "Custom start date in YYYY-MM-DD format"
          },
          custom_end_date: %{
            type: "string",
            description: "Custom end date in YYYY-MM-DD format"
          },
          event_type: %{
            type: "string",
            description: "Filter by event type: meeting, call, appointment, deadline",
            enum: ["meeting", "call", "appointment", "deadline"]
          },
          max_results: %{
            type: "integer",
            description: "Maximum number of event results (default: 10)",
            minimum: 1,
            maximum: 20
          }
        },
        required: ["query"]
      }
    }
  end

  @doc """
  Create tool for answering "who mentioned X" type questions.
  """
  def create_find_mentions_tool() do
    %Function{
      name: "find_mentions",
      description:
        "Find who mentioned a specific person, topic, or thing in communications. Use this for questions like 'who mentioned John', 'who talked about the project', or 'who referenced the deadline'.",
      parameters_schema: %{
        type: "object",
        properties: %{
          mention_target: %{
            type: "string",
            description: "The person, topic, or thing that was mentioned"
          },
          context: %{
            type: "string",
            description: "Additional context about what type of mentions to look for"
          },
          time_range: %{
            type: "string",
            description: "Time range for search: recent, this_week, this_month, this_year",
            enum: ["recent", "this_week", "this_month", "this_year"]
          },
          include_quotes: %{
            type: "boolean",
            description: "Whether to include direct quotes from the mentions (default: true)"
          },
          max_people: %{
            type: "integer",
            description: "Maximum number of people to return (default: 10)",
            minimum: 1,
            maximum: 20
          }
        },
        required: ["mention_target"]
      }
    }
  end

  @doc """
  Create tool for temporal search (when questions).
  """
  def create_when_search_tool() do
    %Function{
      name: "when_search",
      description:
        "Find when specific events, communications, or activities occurred. Use this for questions about timing, dates, schedules, or temporal relationships.",
      parameters_schema: %{
        type: "object",
        properties: %{
          query: %{
            type: "string",
            description: "What you want to find the timing of"
          },
          timeframe: %{
            type: "string",
            description: "General timeframe to search within",
            enum: ["recent", "this_week", "this_month", "last_month", "this_year", "all_time"]
          },
          event_type: %{
            type: "string",
            description:
              "Type of event to search for: communication, meeting, deadline, decision",
            enum: ["communication", "meeting", "deadline", "decision", "any"]
          },
          max_results: %{
            type: "integer",
            description: "Maximum number of results (default: 10)",
            minimum: 1,
            maximum: 20
          }
        },
        required: ["query"]
      }
    }
  end

  @doc """
  Execute RAG search tool function.
  """
  def execute_rag_search(user_id, args) do
    query = Map.get(args, "query")
    search_type = Map.get(args, "search_type", "general")
    max_results = Map.get(args, "max_results", 10)
    time_range = Map.get(args, "time_range")

    Logger.debug("Executing RAG search: #{query} (type: #{search_type})")

    opts = [
      max_results: max_results,
      include_sources: true
    ]

    # Add time range filter if specified
    opts =
      if time_range do
        time_filter = parse_time_range(time_range)
        Keyword.put(opts, :filters, %{"date_range" => time_filter})
      else
        opts
      end

    # Execute search based on type
    case search_type do
      "person" ->
        person_identifier = extract_person_from_query(query)

        if person_identifier do
          Search.person_search(user_id, person_identifier, opts)
        else
          Search.pattern_search(user_id, "who_mentioned", query, opts)
        end

      "temporal" ->
        Search.pattern_search(user_id, "recent_activity", query, opts)

      "contact" ->
        Search.person_search(user_id, query, opts)

      "scheduling" ->
        Search.pattern_search(user_id, "contact_related", query, opts)

      _ ->
        # General search
        Retriever.retrieve_context(user_id, query, opts)
    end
    |> format_rag_response(args)
  end

  @doc """
  Execute find people tool function.
  """
  def execute_find_people(user_id, args) do
    person_identifier = Map.get(args, "person_identifier")
    include_communications = Map.get(args, "include_communications", true)
    max_communications = Map.get(args, "max_communications", 5)

    Logger.debug("Finding person: #{person_identifier}")

    # Search for person
    case Search.person_search(user_id, person_identifier, limit: max_communications) do
      {:ok, results} ->
        # Format person information
        person_info = format_person_information(results, person_identifier)

        # Get additional communications if requested
        communications =
          if include_communications do
            get_person_communications(user_id, person_identifier, max_communications)
          else
            []
          end

        response = %{
          person: person_info,
          communications: communications,
          found: true,
          result_count: length(results)
        }

        {:ok, response}

      {:error, _} ->
        response = %{
          person: nil,
          communications: [],
          found: false,
          result_count: 0,
          message: "Person '#{person_identifier}' not found in your data"
        }

        {:ok, response}
    end
  end

  @doc """
  Execute search emails tool function.
  """
  def execute_search_emails(user_id, args) do
    query = Map.get(args, "query")
    sender = Map.get(args, "sender")
    recipient = Map.get(args, "recipient")
    date_range = Map.get(args, "date_range")
    custom_start_date = Map.get(args, "custom_start_date")
    custom_end_date = Map.get(args, "custom_end_date")
    max_results = Map.get(args, "max_results", 10)

    Logger.debug("Searching emails: #{query}")

    # Build filters
    filters = %{"source" => "gmail"}

    # Add sender filter
    filters =
      if sender do
        Map.put(filters, "person_email", sender)
      else
        filters
      end

    # Add date range filter
    filters =
      if date_range do
        time_filter = parse_email_date_range(date_range, custom_start_date, custom_end_date)
        Map.put(filters, "date_range", time_filter)
      else
        filters
      end

    # Add keyword filter
    filters =
      if query do
        keywords = extract_keywords(query)
        Map.put(filters, "keywords", keywords)
      else
        filters
      end

    opts = [
      filters: filters,
      max_results: max_results,
      include_sources: true
    ]

    # Execute search
    case Search.search_embeddings(user_id, nil, opts) do
      {:ok, results} ->
        email_results = format_email_results(results)

        response = %{
          emails: email_results,
          found: not Enum.empty?(email_results),
          result_count: length(email_results),
          search_terms: query
        }

        {:ok, response}

      error ->
        error
    end
  end

  @doc """
  Execute search calendar tool function.
  """
  def execute_search_calendar(user_id, args) do
    query = Map.get(args, "query")
    attendees = Map.get(args, "attendees", [])
    date_range = Map.get(args, "date_range")
    custom_start_date = Map.get(args, "custom_start_date")
    custom_end_date = Map.get(args, "custom_end_date")
    event_type = Map.get(args, "event_type")
    max_results = Map.get(args, "max_results", 10)

    Logger.debug("Searching calendar: #{query}")

    # Build filters
    filters = %{"source" => "calendar"}

    # Add date range filter
    filters =
      if date_range do
        time_filter = parse_calendar_date_range(date_range, custom_start_date, custom_end_date)
        Map.put(filters, "date_range", time_filter)
      else
        filters
      end

    # Add attendee filter
    filters =
      if not Enum.empty?(attendees) do
        Map.put(filters, "emails", attendees)
      else
        filters
      end

    # Add keyword filter
    filters =
      if query do
        keywords = extract_keywords(query)
        Map.put(filters, "keywords", keywords)
      else
        filters
      end

    # Add event type filter
    filters =
      if event_type do
        Map.put(filters, "keywords", [event_type | Map.get(filters, "keywords", [])])
      else
        filters
      end

    opts = [
      filters: filters,
      max_results: max_results,
      include_sources: true
    ]

    # Execute search
    case Search.search_embeddings(user_id, nil, opts) do
      {:ok, results} ->
        calendar_results = format_calendar_results(results)

        response = %{
          events: calendar_results,
          found: not Enum.empty?(calendar_results),
          result_count: length(calendar_results),
          search_terms: query
        }

        {:ok, response}

      error ->
        error
    end
  end

  @doc """
  Execute find mentions tool function.
  """
  def execute_find_mentions(user_id, args) do
    mention_target = Map.get(args, "mention_target")
    context = Map.get(args, "context", "")
    time_range = Map.get(args, "time_range", "recent")
    include_quotes = Map.get(args, "include_quotes", true)
    max_people = Map.get(args, "max_people", 10)

    Logger.debug("Finding mentions of: #{mention_target}")

    # Build search query
    search_query = "who mentioned #{mention_target}"

    if context != "" do
      search_query = search_query <> " #{context}"
    end

    # Build options
    opts = [
      # Get more results to find multiple people
      max_results: max_people * 3,
      include_sources: include_quotes
    ]

    # Add time range filter
    opts =
      if time_range do
        time_filter = parse_time_range(time_range)
        Keyword.put(opts, :filters, %{"date_range" => time_filter})
      else
        opts
      end

    # Execute search
    case Search.pattern_search(user_id, "who_mentioned", search_query, opts) do
      {:ok, results} ->
        # Group by person and format
        mentions_by_person = group_mentions_by_person(results, mention_target)

        response = %{
          mention_target: mention_target,
          mentions: mentions_by_person,
          found: not Enum.empty?(mentions_by_person),
          people_count: length(mentions_by_person),
          total_mentions: total_mention_count(mentions_by_person),
          time_range: time_range
        }

        {:ok, response}

      error ->
        error
    end
  end

  @doc """
  Execute when search tool function.
  """
  def execute_when_search(user_id, args) do
    query = Map.get(args, "query")
    timeframe = Map.get(args, "timeframe", "recent")
    event_type = Map.get(args, "event_type", "any")
    max_results = Map.get(args, "max_results", 10)

    Logger.debug("Searching when: #{query}")

    # Build temporal search
    case generate_embedding(query) do
      {:ok, embedding} ->
        time_range = parse_when_timeframe(timeframe)

        case Search.temporal_search(
               user_id,
               embedding,
               time_range.start_date,
               time_range.end_date,
               max_results: max_results,
               include_sources: true
             ) do
          {:ok, results} ->
            temporal_results = format_temporal_results(results, event_type)

            response = %{
              query: query,
              timeframe: timeframe,
              results: temporal_results,
              found: not Enum.empty?(temporal_results),
              result_count: length(temporal_results),
              time_span: time_range
            }

            {:ok, response}

          error ->
            error
        end

      {:error, reason} ->
        Logger.error("Failed to generate embedding for when search: #{inspect(reason)}")
        {:ok, %{error: "Unable to process temporal search", query: query}}
    end
  end

  # Helper functions

  defp format_rag_response(result, args) do
    case result do
      {:ok, context_results} ->
        # Build answer from context
        answer =
          AnswerBuilder.build_answer(Map.get(args, "query"), context_results,
            style: :comprehensive,
            include_citations: true
          )

        {:ok, answer}

      error ->
        error
    end
  end

  defp parse_time_range(time_range) do
    now = DateTime.utc_now()

    case time_range do
      "recent" ->
        start_date = DateTime.add(now, -7 * 24 * 60 * 60, :second)
        {start_date, now}

      "this_week" ->
        {TimeHelpers.beginning_of_week(now), TimeHelpers.end_of_week(now)}

      "this_month" ->
        {TimeHelpers.beginning_of_month(now), TimeHelpers.end_of_month(now)}

      "this_year" ->
        {TimeHelpers.beginning_of_year(now), TimeHelpers.end_of_year(now)}

      _ ->
        # Default to recent
        start_date = DateTime.add(now, -7 * 24 * 60 * 60, :second)
        {start_date, now}
    end
  end

  defp extract_person_from_query(query) do
    # Simple person extraction - could be enhanced
    case Regex.run(~r/\b([A-Z][a-z]+(?:\s+[A-Z][a-z]+)?)\b/, query) do
      [_, person] -> person
      _ -> nil
    end
  end

  defp format_person_information(results, person_identifier) do
    if Enum.empty?(results) do
      %{
        name: person_identifier,
        email: nil,
        source_count: 0,
        last_contact: nil
      }
    else
      top_result = hd(results)

      %{
        name: top_result.person_name || person_identifier,
        email: top_result.person_email,
        source_count: length(results),
        last_contact: top_result.inserted_at,
        confidence: Map.get(top_result, :person_score, 0.0)
      }
    end
  end

  defp get_person_communications(user_id, person_identifier, max_results) do
    # Get recent communications with this person
    case Search.person_search(user_id, person_identifier, limit: max_results) do
      {:ok, results} ->
        Enum.map(results, fn result ->
          %{
            text: extract_relevant_snippet(result.text),
            source: result.source,
            date: result.inserted_at,
            confidence: Map.get(result, :relevance_score, 0.0)
          }
        end)

      _ ->
        []
    end
  end

  defp extract_relevant_snippet(text) do
    words = String.split(text, " ")

    cond do
      length(words) <= 40 ->
        text

      length(words) <= 80 ->
        text

      true ->
        words
        |> Enum.take(40)
        |> Enum.join(" ")
        |> Kernel.<>("...")
    end
  end

  defp parse_email_date_range(date_range, custom_start, custom_end) do
    case date_range do
      "custom" ->
        {parse_date_string(custom_start), parse_date_string(custom_end)}

      "last_week" ->
        now = DateTime.utc_now()
        start_date = DateTime.add(now, -7 * 24 * 60 * 60, :second)
        {start_date, now}

      "last_month" ->
        now = DateTime.utc_now()
        start_date = DateTime.add(now, -30 * 24 * 60 * 60, :second)
        {start_date, now}

      "last_quarter" ->
        now = DateTime.utc_now()
        start_date = DateTime.add(now, -90 * 24 * 60 * 60, :second)
        {start_date, now}

      _ ->
        # Default to last month
        now = DateTime.utc_now()
        start_date = DateTime.add(now, -30 * 24 * 60 * 60, :second)
        {start_date, now}
    end
  end

  defp parse_calendar_date_range(date_range, custom_start, custom_end) do
    # Similar to email date range but optimized for calendar events
    parse_email_date_range(date_range, custom_start, custom_end)
  end

  defp parse_date_string(date_string) when is_binary(date_string) do
    case Date.from_iso8601(date_string) do
      {:ok, date} -> DateTime.new!(date, ~T[00:00:00])
      {:error, _} -> DateTime.utc_now()
    end
  end

  defp parse_date_string(_), do: DateTime.utc_now()

  defp extract_keywords(query) do
    query
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9\s]/, " ")
    |> String.split()
    |> Enum.filter(fn word -> String.length(word) > 2 end)
    |> Enum.uniq()
    |> Enum.take(5)
  end

  defp format_email_results(results) do
    Enum.map(results, fn result ->
      %{
        id: result.id,
        subject: extract_subject_from_text(result.text),
        sender: result.person_name || result.person_email,
        date: result.inserted_at,
        snippet: extract_relevant_snippet(result.text),
        confidence: Map.get(result, :relevance_score, 0.0),
        source_info: Map.get(result, :source_info, %{})
      }
    end)
  end

  defp extract_subject_from_text(text) do
    # Try to extract subject from email text
    lines = String.split(text, "\n")

    subject_line =
      Enum.find(lines, fn line ->
        String.starts_with?(String.downcase(String.trim(line)), "subject:")
      end)

    if subject_line do
      subject_line
      |> String.trim()
      |> String.replace_prefix("Subject:", "")
      |> String.replace_prefix("subject:", "")
      |> String.trim()
    else
      # Take first line as potential subject
      hd(lines) |> String.trim()
    end
  end

  defp format_calendar_results(results) do
    Enum.map(results, fn result ->
      %{
        id: result.id,
        title: extract_event_title(result.text),
        date: result.inserted_at,
        attendees: extract_attendees(result.text),
        description: extract_relevant_snippet(result.text),
        confidence: Map.get(result, :relevance_score, 0.0),
        source_info: Map.get(result, :source_info, %{})
      }
    end)
  end

  defp extract_event_title(text) do
    # Try to extract event title from calendar text
    lines = String.split(text, "\n")

    title_line =
      Enum.find(lines, fn line ->
        not String.starts_with?(String.downcase(String.trim(line)), "when:") and
          not String.starts_with?(String.downcase(String.trim(line)), "where:") and
          not String.starts_with?(String.downcase(String.trim(line)), "attendees:")
      end)

    if title_line do
      String.trim(title_line)
    else
      hd(lines) |> String.trim()
    end
  end

  defp extract_attendees(text) do
    # Extract attendee information from text
    lines = String.split(text, "\n")

    attendees_line =
      Enum.find(lines, fn line ->
        String.starts_with?(String.downcase(String.trim(line)), "attendees:")
      end)

    if attendees_line do
      attendees_line
      |> String.replace_prefix("Attendees:", "")
      |> String.replace_prefix("attendees:", "")
      |> String.split(",")
      |> Enum.map(&String.trim/1)
      |> Enum.filter(&(&1 != ""))
    else
      []
    end
  end

  defp group_mentions_by_person(results, mention_target) do
    Enum.group_by(results, fn result ->
      result.person_name || result.person_email || "Unknown"
    end)
    |> Enum.map(fn {person, person_results} ->
      relevant_mentions =
        person_results
        |> Enum.filter(fn result -> contains_mention?(result.text, mention_target) end)
        |> Enum.take(3)

      %{
        person: person,
        mentions:
          Enum.map(relevant_mentions, fn result ->
            %{
              text: extract_relevant_snippet(result.text),
              date: result.inserted_at,
              source: result.source,
              confidence: Map.get(result, :relevance_score, 0.0)
            }
          end),
        mention_count: length(relevant_mentions)
      }
    end)
    |> Enum.filter(fn person_data -> person_data.mention_count > 0 end)
    |> Enum.sort_by(&(-&1.mention_count))
  end

  defp contains_mention?(text, mention_target) do
    text_lower = String.downcase(text)
    target_lower = String.downcase(mention_target)

    String.contains?(text_lower, target_lower)
  end

  defp total_mention_count(mentions_by_person) do
    Enum.sum(Enum.map(mentions_by_person, & &1.mention_count))
  end

  defp parse_when_timeframe(timeframe) do
    now = DateTime.utc_now()

    case timeframe do
      "recent" ->
        start_date = DateTime.add(now, -7 * 24 * 60 * 60, :second)
        %{start_date: start_date, end_date: now, label: "Last 7 days"}

      "this_week" ->
        %{
          start_date: TimeHelpers.beginning_of_week(now),
          end_date: TimeHelpers.end_of_week(now),
          label: "This week"
        }

      "this_month" ->
        %{
          start_date: TimeHelpers.beginning_of_month(now),
          end_date: TimeHelpers.end_of_month(now),
          label: "This month"
        }

      "last_month" ->
        start_date = DateTime.add(now, -30 * 24 * 60 * 60, :second)
        %{start_date: start_date, end_date: now, label: "Last month"}

      "this_year" ->
        %{
          start_date: TimeHelpers.beginning_of_year(now),
          end_date: TimeHelpers.end_of_year(now),
          label: "This year"
        }

      "all_time" ->
        # Return a very wide range
        start_date = DateTime.add(now, -365 * 24 * 60 * 60, :second)
        %{start_date: start_date, end_date: now, label: "Past year"}

      _ ->
        # Default to recent
        start_date = DateTime.add(now, -7 * 24 * 60 * 60, :second)
        %{start_date: start_date, end_date: now, label: "Last 7 days"}
    end
  end

  defp format_temporal_results(results, event_type) do
    filtered_results =
      if event_type == "any" do
        results
      else
        Enum.filter(results, fn result ->
          text_lower = String.downcase(result.text)
          String.contains?(text_lower, String.downcase(event_type))
        end)
      end

    Enum.map(filtered_results, fn result ->
      %{
        id: result.id,
        date: result.inserted_at,
        description: extract_relevant_snippet(result.text),
        source: result.source,
        person: result.person_name || result.person_email,
        confidence: Map.get(result, :relevance_score, 0.0),
        source_info: Map.get(result, :source_info, %{})
      }
    end)
  end

  defp generate_embedding(text) do
    # This would integrate with the embedding generation system
    # For now, return a placeholder
    {:ok, List.duplicate(0.1, 1536)}
  end
end
