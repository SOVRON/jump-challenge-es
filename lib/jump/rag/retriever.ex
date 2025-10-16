defmodule Jump.RAG.Retriever do
  @moduledoc """
  Intelligent retrieval system for RAG with context-aware query processing.
  """

  alias Jump.RAG.Search
  alias Jump.RAG.Chunk
  alias Jump.TimeHelpers
  require Logger

  @doc """
  Retrieve relevant context for a user query with intelligent query processing.
  """
  def retrieve_context(user_id, query, opts \\ []) do
    max_results = Keyword.get(opts, :max_results, 10)
    # tokens
    context_window = Keyword.get(opts, :context_window, 4000)
    include_sources = Keyword.get(opts, :include_sources, true)

    # Process and understand the query
    processed_query = process_query(query)

    # Determine search strategy
    search_strategy = determine_search_strategy(processed_query)

    # Execute retrieval based on strategy
    case execute_retrieval(user_id, processed_query, search_strategy, opts) do
      {:ok, raw_results} ->
        # Post-process and rank results
        context_results =
          post_process_results(raw_results, processed_query, context_window, include_sources)

        {:ok, context_results}

      error ->
        error
    end
  end

  @doc """
  Retrieve context for multi-turn conversations with conversation history.
  """
  def retrieve_with_history(user_id, query, conversation_history, opts \\ []) do
    # Extract context from conversation history
    conversation_context = extract_conversation_context(conversation_history)

    # Enhance query with conversation context
    enhanced_query = enhance_query_with_context(query, conversation_context)

    # Retrieve with enhanced query
    retrieve_context(
      user_id,
      enhanced_query,
      Keyword.put(opts, :conversation_context, conversation_context)
    )
  end

  @doc """
  Retrieve context for specific entities (people, companies, topics).
  """
  def retrieve_entity_context(user_id, entity_type, entity_name, opts \\ []) do
    case entity_type do
      :person ->
        Search.person_search(user_id, entity_name, opts)

      :company ->
        retrieve_company_context(user_id, entity_name, opts)

      :topic ->
        retrieve_topic_context(user_id, entity_name, opts)

      :event ->
        retrieve_event_context(user_id, entity_name, opts)

      _ ->
        {:error, :unsupported_entity_type}
    end
  end

  @doc """
  Retrieve temporal context for date ranges and time-based queries.
  """
  def retrieve_temporal_context(user_id, query, time_range, opts \\ []) do
    {start_date, end_date} = parse_time_range(time_range)

    # Generate embedding for temporal query
    case generate_embedding(query) do
      {:ok, embedding} ->
        Search.temporal_search(user_id, embedding, start_date, end_date, opts)

      {:error, reason} ->
        Logger.warning("Failed to generate embedding for temporal query: #{inspect(reason)}")
        # Fallback to keyword search with date filter
        filters = Keyword.get(opts, :filters, %{})
        date_filters = Map.put(filters, "date_range", {start_date, end_date})

        Search.search_embeddings(user_id, nil, Keyword.put(opts, :filters, date_filters))
    end
  end

  @doc """
  Retrieve contextual information for meeting scheduling.
  """
  def retrieve_scheduling_context(user_id, participants, opts \\ []) do
    # Get context about participants
    participant_context =
      participants
      |> Enum.map(fn participant ->
        case Search.person_search(user_id, participant, limit: 3) do
          {:ok, results} -> {participant, results}
          {:error, _} -> {participant, []}
        end
      end)
      |> Enum.into(%{})

    # Get recent communication with participants
    communication_context = get_participant_communication(user_id, participants, opts)

    # Get calendar availability context
    calendar_context = get_calendar_context(user_id, participants, opts)

    context = %{
      participants: participant_context,
      communication: communication_context,
      calendar: calendar_context,
      timestamp: DateTime.utc_now()
    }

    {:ok, context}
  end

  # Private functions

  defp process_query(query) do
    %{
      original: query,
      normalized: normalize_query(query),
      intent: classify_query_intent(query),
      entities: extract_entities(query),
      time_references: extract_time_references(query),
      sentiment: analyze_sentiment(query),
      complexity: calculate_query_complexity(query)
    }
  end

  defp normalize_query(query) do
    query
    |> String.trim()
    |> String.downcase()
    |> remove_stop_words()
    |> fix_common_typos()
  end

  defp remove_stop_words(query) do
    stop_words = [
      "the",
      "a",
      "an",
      "and",
      "or",
      "but",
      "in",
      "on",
      "at",
      "to",
      "for",
      "of",
      "with",
      "by"
    ]

    query
    |> String.split()
    |> Enum.filter(fn word -> not Enum.member?(stop_words, word) end)
    |> Enum.join(" ")
  end

  defp fix_common_typos(query) do
    # Simple typo corrections
    query
    |> String.replace("shedule", "schedule")
    |> String.replace("calender", "calendar")
    |> String.replace("emaill", "email")
    |> String.replace("contac", "contact")
  end

  defp classify_query_intent(query) do
    cond do
      String.contains?(query, "who") -> :person_search
      String.contains?(query, "when") -> :temporal_search
      String.contains?(query, "where") -> :location_search
      String.contains?(query, "what") -> :information_search
      String.contains?(query, "how") -> :procedural_search
      String.contains?(query, "schedule") or String.contains?(query, "meeting") -> :scheduling
      String.contains?(query, "email") or String.contains?(query, "send") -> :communication
      String.contains?(query, "contact") or String.contains?(query, "hubspot") -> :crm
      true -> :general_search
    end
  end

  defp extract_entities(query) do
    # Extract people, organizations, locations, dates, etc.
    %{
      people: extract_people(query),
      organizations: extract_organizations(query),
      dates: extract_dates(query),
      emails: extract_emails(query),
      phone_numbers: extract_phone_numbers(query)
    }
  end

  defp extract_people(query) do
    # Simple person name extraction (could be enhanced with NLP)
    person_pattern = ~r/\b([A-Z][a-z]+\s+[A-Z][a-z]+)\b/
    Regex.scan(person_pattern, query) |> Enum.map(&hd/1)
  end

  defp extract_organizations(_query) do
    # Organization extraction would go here
    []
  end

  defp extract_dates(query) do
    # Date extraction patterns
    date_patterns = [
      # MM/DD/YYYY
      ~r/\b\d{1,2}\/\d{1,2}\/\d{4}\b/,
      # YYYY-MM-DD
      ~r/\b\d{4}-\d{2}-\d{2}\b/,
      # Month DD, YYYY
      ~r/\b(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\s+\d{1,2},?\s+\d{4}\b/i
    ]

    Enum.flat_map(date_patterns, fn pattern ->
      Regex.scan(pattern, query) |> Enum.map(&hd/1)
    end)
  end

  defp extract_emails(query) do
    email_pattern = ~r/\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b/
    Regex.scan(email_pattern, query) |> Enum.map(&hd/1)
  end

  defp extract_phone_numbers(_query) do
    # Phone number extraction would go here
    []
  end

  defp extract_time_references(query) do
    time_patterns = [
      ~r/\b(?:today|tomorrow|yesterday|yesterday|last week|next week|this week|next month|last month)\b/i,
      ~r/\b\d{1,2}\s*(?:am|pm|AM|PM)\b/i,
      ~r/\b(?:morning|afternoon|evening|night|noon|midnight)\b/i
    ]

    Enum.flat_map(time_patterns, fn pattern ->
      Regex.scan(pattern, query) |> Enum.map(&hd/1)
    end)
  end

  defp analyze_sentiment(_query) do
    # Sentiment analysis would go here
    :neutral
  end

  defp calculate_query_complexity(query) do
    word_count = length(String.split(query))

    cond do
      word_count <= 3 -> :simple
      word_count <= 7 -> :moderate
      word_count <= 15 -> :complex
      true -> :very_complex
    end
  end

  defp determine_search_strategy(processed_query) do
    case processed_query.intent do
      :person_search ->
        if not Enum.empty?(processed_query.entities.people) do
          {:person_search, hd(processed_query.entities.people)}
        else
          {:pattern_search, "who_mentioned"}
        end

      :temporal_search ->
        {:temporal_search, processed_query.time_references}

      :scheduling ->
        {:scheduling, processed_query.entities.people}

      :communication ->
        {:source_specific, "gmail"}

      :crm ->
        {:source_specific, "hubspot"}

      _ ->
        {:hybrid_search, processed_query.normalized}
    end
  end

  defp execute_retrieval(user_id, processed_query, search_strategy, opts) do
    case search_strategy do
      {:person_search, person_name} ->
        Search.person_search(user_id, person_name, opts)

      {:temporal_search, time_refs} ->
        time_range = determine_time_range(time_refs)
        retrieve_temporal_context(user_id, processed_query.original, time_range, opts)

      {:scheduling, participants} ->
        retrieve_scheduling_context(user_id, participants, opts)

      {:pattern_search, pattern} ->
        Search.pattern_search(user_id, pattern, processed_query.original, opts)

      {:source_specific, source} ->
        filters = Map.put(Keyword.get(opts, :filters, %{}), "source", source)
        Search.search_embeddings(user_id, nil, Keyword.put(opts, :filters, filters))

      {:hybrid_search, query_text} ->
        case generate_embedding(processed_query.original) do
          {:ok, embedding} ->
            Search.hybrid_search(user_id, query_text, embedding, opts)

          {:error, _} ->
            {:ok, []}
        end
    end
  end

  defp post_process_results(results, processed_query, context_window, include_sources) do
    # Rank results by relevance
    ranked_results = rank_results_by_relevance(results, processed_query)

    # Select best results within context window
    selected_results = select_best_within_context(ranked_results, context_window)

    # Add source information if requested
    final_results =
      if include_sources do
        Enum.map(selected_results, &add_source_metadata/1)
      else
        selected_results
      end

    # Add retrieval metadata
    Enum.map(final_results, fn result ->
      Map.put(result, :retrieval_metadata, %{
        query_intent: processed_query.intent,
        retrieval_time: DateTime.utc_now(),
        rank: get_result_rank(result, selected_results)
      })
    end)
  end

  defp rank_results_by_relevance(results, processed_query) do
    # Score results based on multiple factors
    Enum.map(results, fn result ->
      score = calculate_relevance_score(result, processed_query)
      Map.put(result, :relevance_score, score)
    end)
    |> Enum.sort_by(&(-&1.relevance_score))
  end

  defp calculate_relevance_score(result, processed_query) do
    base_score =
      Map.get(result, :similarity_score, 0.0) || Map.get(result, :combined_score, 0.0) || 0.0

    # Boost scores based on query intent
    intent_boost = calculate_intent_boost(result, processed_query.intent)

    # Recency boost
    recency_boost = Map.get(result, :recency_bonus, 0.0) || 0.0

    # Entity matching boost
    entity_boost = calculate_entity_boost(result, processed_query.entities)

    base_score + intent_boost + recency_boost + entity_boost
  end

  defp calculate_intent_boost(result, intent) do
    case intent do
      :person_search when result.person_email != nil -> 0.2
      :communication when result.source == "gmail" -> 0.15
      :crm when result.source == "hubspot" -> 0.15
      _ -> 0.0
    end
  end

  defp calculate_entity_boost(result, entities) do
    people_boost =
      if(entities.people && Enum.any?(entities.people, &person_match?(result, &1)),
        do: 0.1,
        else: 0.0
      )

    email_boost =
      if(entities.emails && Enum.any?(entities.emails, &email_match?(result, &1)),
        do: 0.15,
        else: 0.0
      )

    entity_score = people_boost + email_boost

    entity_score
  end

  defp person_match?(result, person_name) do
    result.person_name &&
      String.contains?(String.downcase(result.person_name), String.downcase(person_name))
  end

  defp email_match?(result, email) do
    result.person_email &&
      String.contains?(String.downcase(result.person_email), String.downcase(email))
  end

  defp select_best_within_context(ranked_results, context_window) do
    # Select results to fit within context window
    {selected_results, _total_tokens} =
      Enum.reduce_while(ranked_results, {[], 0}, fn result, {acc, total_tokens} ->
        result_tokens = estimate_token_count(result.text)
        new_total = total_tokens + result_tokens

        if new_total <= context_window do
          {:cont, {[result | acc], new_total}}
        else
          {:halt, {acc, total_tokens}}
        end
      end)

    Enum.reverse(selected_results)
  end

  defp estimate_token_count(text) do
    # Rough token estimation (could be enhanced with proper tokenizer)
    word_count = length(String.split(text))
    # Approximate token count
    round(word_count * 1.3)
  end

  defp add_source_metadata(result) do
    source_info = get_source_information(result)
    Map.put(result, :source_info, source_info)
  end

  defp get_source_information(result) do
    case result.source do
      "gmail" ->
        %{
          type: "email",
          icon: "📧",
          color: "#ea4335",
          label: "Email Message"
        }

      "hubspot" ->
        %{
          type: "crm",
          icon: "🏢",
          color: "#ff7a59",
          label: "HubSpot Contact"
        }

      "calendar" ->
        %{
          type: "calendar",
          icon: "📅",
          color: "#4285f4",
          label: "Calendar Event"
        }

      _ ->
        %{
          type: "document",
          icon: "📄",
          color: "#5f6368",
          label: "Document"
        }
    end
  end

  defp get_result_rank(result, results) do
    Enum.find_index(results, &(&1.id == result.id)) + 1
  end

  defp extract_conversation_context(conversation_history) do
    # Extract relevant context from conversation history
    recent_messages = Enum.take(conversation_history, -5)

    %{
      entities: extract_entities_from_history(recent_messages),
      topics: extract_topics_from_history(recent_messages),
      sentiment: analyze_conversation_sentiment(recent_messages),
      last_topics: get_last_mentioned_topics(recent_messages)
    }
  end

  defp extract_entities_from_history(_history) do
    # Extract entities from conversation history
    %{}
  end

  defp extract_topics_from_history(_history) do
    # Extract topics from conversation history
    []
  end

  defp analyze_conversation_sentiment(_history) do
    # Analyze overall conversation sentiment
    :neutral
  end

  defp get_last_mentioned_topics(_history) do
    # Get topics mentioned in recent conversation
    []
  end

  defp enhance_query_with_context(query, conversation_context) do
    # Enhance query with conversation context
    "#{query} #{build_context_string(conversation_context)}"
  end

  defp build_context_string(_conversation_context) do
    # Build context string from conversation metadata
    ""
  end

  defp retrieve_company_context(user_id, company_name, opts) do
    # Search for company-related information
    filters = Keyword.get(opts, :filters, %{})
    company_filters = Map.put(filters, "keywords", [company_name])

    Search.search_embeddings(user_id, nil, Keyword.put(opts, :filters, company_filters))
  end

  defp retrieve_topic_context(user_id, topic_name, opts) do
    # Search for topic-specific information
    Search.pattern_search(user_id, "emails_about", topic_name, opts)
  end

  defp retrieve_event_context(user_id, event_name, opts) do
    # Search for event-related information
    filters = Keyword.get(opts, :filters, %{})
    event_filters = Map.put(filters, "source", "calendar")

    Search.search_embeddings(user_id, nil, Keyword.put(opts, :filters, event_filters))
  end

  defp parse_time_range(time_range) do
    # Parse time range specification
    case time_range do
      "recent" ->
        start_date = DateTime.add(DateTime.utc_now(), -7 * 24 * 60 * 60, :second)
        {start_date, DateTime.utc_now()}

      "this_month" ->
        now = DateTime.utc_now()
        start_date = TimeHelpers.beginning_of_month(now)
        {start_date, now}

      _ ->
        # Default to last 30 days
        start_date = DateTime.add(DateTime.utc_now(), -30 * 24 * 60 * 60, :second)
        {start_date, DateTime.utc_now()}
    end
  end

  defp determine_time_range(time_references) do
    # Determine time range from time references
    now = DateTime.utc_now()

    cond do
      Enum.any?(time_references, &String.contains?(&1, "today")) ->
        {TimeHelpers.beginning_of_day(now), TimeHelpers.end_of_day(now)}

      Enum.any?(time_references, &String.contains?(&1, "week")) ->
        {TimeHelpers.beginning_of_week(now), TimeHelpers.end_of_week(now)}

      true ->
        # Default to recent
        "recent"
    end
  end

  defp get_participant_communication(user_id, participants, opts) do
    # Get recent communication with participants
    Enum.map(participants, fn participant ->
      case Search.person_search(user_id, participant, limit: 5) do
        {:ok, results} -> {participant, results}
        {:error, _} -> {participant, []}
      end
    end)
    |> Enum.into(%{})
  end

  defp get_calendar_context(_user_id, _participants, _opts) do
    # Get calendar context (would integrate with calendar module)
    %{
      availability: "unknown",
      recent_events: [],
      upcoming_events: []
    }
  end

  @doc """
  Search and retrieve with enhanced parameters for agent tools.
  """
  def search_and_retrieve(
        user_id,
        query,
        search_type \\ "general",
        max_results \\ 10,
        time_range \\ "recent"
      ) do
    opts = [
      max_results: max_results,
      search_type: search_type,
      time_range: time_range,
      include_sources: true
    ]

    case retrieve_context(user_id, query, opts) do
      {:ok, context} ->
        # Convert context to results format expected by tools
        results = convert_context_to_results(context)
        {:ok, results}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp generate_embedding(text) do
    # This would integrate with the embedding generation system
    # For now, return a placeholder
    {:ok, List.duplicate(0.1, 1536)}
  end

  # Convert context format to results format for tools
  defp convert_context_to_results(context) when is_list(context) do
    # Context is already a list of results from retrieve_context
    context
  end

  defp convert_context_to_results(%{chunks: chunks}) when is_list(chunks) do
    # Handle legacy map format if needed
    chunks
  end
end
