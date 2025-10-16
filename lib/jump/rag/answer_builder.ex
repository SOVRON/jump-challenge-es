defmodule Jump.RAG.AnswerBuilder do
  @moduledoc """
  Constructs intelligent answers from RAG results with proper citations and formatting.
  """

  alias Jump.RAG.Retriever
  require Logger

  @doc """
  Build an answer from retrieved context with proper citations.
  """
  def build_answer(query, context_results, opts \\ []) do
    answer_style = Keyword.get(opts, :style, :comprehensive)
    include_citations = Keyword.get(opts, :include_citations, true)
    max_length = Keyword.get(opts, :max_length, 500)
    confidence_threshold = Keyword.get(opts, :confidence_threshold, 0.7)

    # Filter results by confidence
    confident_results = filter_by_confidence(context_results, confidence_threshold)

    if Enum.empty?(confident_results) do
      build_no_results_answer(query, opts)
    else
      case answer_style do
        :concise -> build_concise_answer(query, confident_results, opts)
        :comprehensive -> build_comprehensive_answer(query, confident_results, opts)
        :bullet_points -> build_bullet_answer(query, confident_results, opts)
        :conversational -> build_conversational_answer(query, confident_results, opts)
        _ -> build_comprehensive_answer(query, confident_results, opts)
      end
    end
  end

  @doc """
  Build an answer for "who mentioned X" type queries.
  """
  def build_who_mentioned_answer(query, context_results, opts \\ []) do
    # Group results by person
    grouped_by_person = group_results_by_person(context_results)

    # Find relevant mentions
    mentions = extract_mentions(grouped_by_person, query)

    # Format answer
    answer_parts =
      Enum.map(mentions, fn {person, person_mentions} ->
        format_person_mention(person, person_mentions, opts)
      end)

    answer =
      if Enum.empty?(answer_parts) do
        "I couldn't find any mentions related to your query."
      else
        "Based on the information I found:\n\n" <> Enum.join(answer_parts, "\n\n")
      end

    %{
      answer: answer,
      style: :who_mentioned,
      sources: extract_sources(context_results),
      confidence: calculate_overall_confidence(context_results),
      person_count: length(grouped_by_person),
      mention_count: total_mentions(mentions)
    }
  end

  @doc """
  Build an answer for temporal queries (when, schedule-related).
  """
  def build_temporal_answer(query, context_results, opts \\ []) do
    # Extract temporal information
    temporal_info = extract_temporal_information(context_results)

    # Organize by time
    organized_info = organize_temporal_info(temporal_info)

    # Format temporal answer
    answer = format_temporal_answer(query, organized_info, opts)

    %{
      answer: answer,
      style: :temporal,
      sources: extract_sources(context_results),
      confidence: calculate_overall_confidence(context_results),
      time_range: determine_time_range(temporal_info),
      event_count: length(temporal_info)
    }
  end

  @doc """
  Build an answer for contact/CRM queries.
  """
  def build_contact_answer(query, context_results, opts \\ []) do
    # Extract contact information
    contact_info = extract_contact_information(context_results)

    # Organize by contact
    organized_contacts = organize_contact_info(contact_info)

    # Format contact answer
    answer = format_contact_answer(query, organized_contacts, opts)

    %{
      answer: answer,
      style: :contact,
      sources: extract_sources(context_results),
      confidence: calculate_overall_confidence(context_results),
      contact_count: length(organized_contacts)
    }
  end

  @doc """
  Build an answer for scheduling/meeting queries.
  """
  def build_scheduling_answer(query, context_results, opts \\ []) do
    # Extract scheduling context
    scheduling_info = extract_scheduling_information(context_results)

    # Analyze availability and constraints
    scheduling_analysis = analyze_scheduling_context(scheduling_info)

    # Format scheduling answer
    answer = format_scheduling_answer(query, scheduling_analysis, opts)

    %{
      answer: answer,
      style: :scheduling,
      sources: extract_sources(context_results),
      confidence: calculate_overall_confidence(context_results),
      suggestions: generate_scheduling_suggestions(scheduling_analysis)
    }
  end

  # Private functions

  defp build_concise_answer(query, context_results, opts) do
    # Extract key information
    # Top 3 results
    key_info = extract_key_information(context_results, 3)

    # Build concise answer
    answer = format_concise_answer(query, key_info, opts)

    %{
      answer: answer,
      style: :concise,
      sources: extract_sources(context_results),
      confidence: calculate_overall_confidence(context_results),
      key_points: length(key_info)
    }
  end

  defp build_comprehensive_answer(query, context_results, opts) do
    # Extract all relevant information
    # Top 10 results
    all_info = extract_key_information(context_results, 10)

    # Organize by themes/topics
    organized_info = organize_by_themes(all_info)

    # Build comprehensive answer
    answer = format_comprehensive_answer(query, organized_info, opts)

    %{
      answer: answer,
      style: :comprehensive,
      sources: extract_sources(context_results),
      confidence: calculate_overall_confidence(context_results),
      theme_count: length(organized_info),
      total_sources: length(context_results)
    }
  end

  defp build_bullet_answer(query, context_results, opts) do
    # Extract bullet-pointable information
    bullet_info = extract_bullet_information(context_results)

    # Format bullet answer
    answer = format_bullet_answer(query, bullet_info, opts)

    %{
      answer: answer,
      style: :bullet_points,
      sources: extract_sources(context_results),
      confidence: calculate_overall_confidence(context_results),
      bullet_count: length(bullet_info)
    }
  end

  defp build_conversational_answer(query, context_results, opts) do
    # Build natural, conversational response
    key_info = extract_key_information(context_results, 5)

    answer = format_conversational_answer(query, key_info, opts)

    %{
      answer: answer,
      style: :conversational,
      sources: extract_sources(context_results),
      confidence: calculate_overall_confidence(context_results),
      key_points: length(key_info)
    }
  end

  defp build_no_results_answer(query, opts) do
    suggestions = generate_search_suggestions(query)

    answer = """
    I couldn't find specific information about "#{query}" in your emails, calendar, or contacts. 

    Here are some suggestions:
    • Try different keywords or rephrase your question
    • Check if the information might be under a different name or topic
    • Make sure the person or event you're asking about is in your connected accounts

    #{format_suggestions(suggestions)}
    """

    %{
      answer: String.trim(answer),
      style: :no_results,
      sources: [],
      confidence: 0.0,
      suggestions: suggestions
    }
  end

  defp filter_by_confidence(results, threshold) do
    Enum.filter(results, fn result ->
      score =
        Map.get(result, :relevance_score, 0.0) || Map.get(result, :similarity_score, 0.0) || 0.0

      score >= threshold
    end)
  end

  defp group_results_by_person(results) do
    Enum.group_by(results, fn result ->
      result.person_name || result.person_email || "Unknown"
    end)
  end

  defp extract_mentions(grouped_by_person, query) do
    # Extract person name from query
    target_person = extract_target_person(query)

    Enum.map(grouped_by_person, fn {person, person_results} ->
      relevant_mentions =
        person_results
        |> Enum.filter(fn result -> is_relevant_mention?(result, query, target_person) end)
        # Limit mentions per person
        |> Enum.take(3)

      {person, relevant_mentions}
    end)
    |> Enum.filter(fn {_person, mentions} -> not Enum.empty?(mentions) end)
  end

  defp extract_target_person(query) do
    case Regex.run(~r/who mentioned\s+(.+?)\s*(?:\.|$|\?)/i, query) do
      [_, person] -> String.trim(person)
      _ -> nil
    end
  end

  defp is_relevant_mention?(result, query, target_person) do
    text_lower = String.downcase(result.text)
    query_lower = String.downcase(query)

    # Check if result contains the target person
    person_mention =
      if target_person do
        String.contains?(text_lower, String.downcase(target_person))
      else
        # Look for any person mentions in the query
        extract_people_from_query(query)
        |> Enum.any?(fn person -> String.contains?(text_lower, String.downcase(person)) end)
      end

    # Check for relevant keywords
    relevant_keywords = extract_relevant_keywords(query)

    keyword_match =
      Enum.any?(relevant_keywords, fn keyword ->
        String.contains?(text_lower, keyword)
      end)

    person_mention or keyword_match
  end

  defp extract_people_from_query(query) do
    # Simple person extraction
    person_pattern = ~r/\b([A-Z][a-z]+(?:\s+[A-Z][a-z]+)?)\b/
    Regex.scan(person_pattern, query) |> Enum.map(&hd/1)
  end

  defp extract_relevant_keywords(query) do
    # Extract keywords that might be relevant to the query
    query
    |> String.downcase()
    |> String.split()
    |> Enum.filter(fn word ->
      String.length(word) > 3 and
        not Enum.member?(["who", "mentioned", "what", "when", "where", "how"], word)
    end)
  end

  defp format_person_mention(person, mentions, opts) do
    include_citations = Keyword.get(opts, :include_citations, true)

    mention_text =
      if length(mentions) == 1 do
        format_single_mention(hd(mentions), include_citations)
      else
        format_multiple_mentions(mentions, include_citations)
      end

    "**#{person}**:\n#{mention_text}"
  end

  defp format_single_mention(mention, include_citations) do
    snippet = extract_relevant_snippet(mention.text)

    if include_citations do
      "#{snippet} *(Source: #{format_source_citation(mention)})*"
    else
      snippet
    end
  end

  defp format_multiple_mentions(mentions, include_citations) do
    formatted_mentions =
      Enum.map(mentions, fn mention ->
        snippet = extract_relevant_snippet(mention.text)

        if include_citations do
          "• #{snippet} *(#{format_source_citation(mention)})*"
        else
          "• #{snippet}"
        end
      end)

    Enum.join(formatted_mentions, "\n")
  end

  defp extract_relevant_snippet(text) do
    # Extract the most relevant part of the text
    words = String.split(text, " ")

    cond do
      length(words) <= 30 ->
        text

      length(words) <= 60 ->
        text

      true ->
        # Take first 30 words and add ellipsis
        words
        |> Enum.take(30)
        |> Enum.join(" ")
        |> Kernel.<>("...")
    end
  end

  defp format_source_citation(result) do
    case result.source do
      "gmail" ->
        date = format_date(result.inserted_at)
        "Email from #{result.person_name || "Unknown"} - #{date}"

      "hubspot" ->
        "HubSpot Contact Record"

      "calendar" ->
        "Calendar Event"

      _ ->
        "Document - #{format_date(result.inserted_at)}"
    end
  end

  defp format_date(datetime) do
    Calendar.strftime(datetime, "%B %d, %Y")
  end

  defp extract_key_information(results, limit) do
    results
    |> Enum.take(limit)
    |> Enum.map(fn result ->
      %{
        text: extract_relevant_snippet(result.text),
        source: result.source,
        person: result.person_name || result.person_email,
        date: result.inserted_at,
        confidence: Map.get(result, :relevance_score, 0.0),
        metadata: Map.get(result, :meta, %{})
      }
    end)
  end

  defp organize_by_themes(info) do
    # Group information by themes/topics
    Enum.group_by(info, fn item ->
      determine_theme(item)
    end)
  end

  defp determine_theme(item) do
    text_lower = String.downcase(item.text)

    cond do
      String.contains?(text_lower, "meeting") or String.contains?(text_lower, "schedule") ->
        "Meetings & Scheduling"

      String.contains?(text_lower, "project") or String.contains?(text_lower, "work") ->
        "Work & Projects"

      String.contains?(text_lower, "family") or String.contains?(text_lower, "personal") ->
        "Personal & Family"

      String.contains?(text_lower, "client") or String.contains?(text_lower, "customer") ->
        "Clients & Customers"

      true ->
        "General"
    end
  end

  defp format_concise_answer(query, key_info, opts) do
    if Enum.empty?(key_info) do
      "I don't have enough information to answer your question about #{query}."
    else
      result = hd(key_info)
      "Based on your information, #{format_simple_answer(query, result, opts)}"
    end
  end

  defp format_simple_answer(query, result, _opts) do
    case determine_query_type(query) do
      :person -> "#{result.person} was mentioned in relation to #{result.text}."
      :time -> "This occurred around #{format_date(result.date)}."
      :topic -> "Regarding #{query}, #{result.text}"
      _ -> "#{result.text}"
    end
  end

  defp determine_query_type(query) do
    cond do
      String.contains?(query, "who") -> :person
      String.contains?(query, "when") -> :time
      String.contains?(query, "what") -> :topic
      true -> :general
    end
  end

  defp format_comprehensive_answer(query, organized_info, opts) do
    if Enum.empty?(organized_info) do
      "I couldn't find comprehensive information about #{query}."
    else
      theme_answers =
        Enum.map(organized_info, fn {theme, items} ->
          format_theme_answer(theme, items, opts)
        end)

      "Here's what I found about **#{query}**:\n\n" <> Enum.join(theme_answers, "\n\n")
    end
  end

  defp format_theme_answer(theme, items, opts) do
    include_citations = Keyword.get(opts, :include_citations, true)

    items_text =
      Enum.map(items, fn item ->
        if include_citations do
          "• #{item.text} *(#{format_source_citation(item)})*"
        else
          "• #{item.text}"
        end
      end)
      |> Enum.join("\n")

    "**#{theme}:**\n#{items_text}"
  end

  defp extract_bullet_information(results) do
    Enum.map(results, fn result ->
      %{
        text: extract_relevant_snippet(result.text),
        source: result.source,
        person: result.person_name || result.person_email,
        date: result.inserted_at,
        confidence: Map.get(result, :relevance_score, 0.0)
      }
    end)
  end

  defp format_bullet_answer(query, bullet_info, opts) do
    include_citations = Keyword.get(opts, :include_citations, true)

    if Enum.empty?(bullet_info) do
      "I couldn't find specific information about #{query}."
    else
      bullets =
        Enum.map(bullet_info, fn item ->
          if include_citations do
            "• #{item.text} *(#{format_source_citation(item)})*"
          else
            "• #{item.text}"
          end
        end)

      "Here's what I found about **#{query}**:\n\n" <> Enum.join(bullets, "\n")
    end
  end

  defp format_conversational_answer(query, key_info, opts) do
    if Enum.empty?(key_info) do
      "I searched through your emails and contacts, but I couldn't find specific information about #{query}. Could you provide more details or try different keywords?"
    else
      "I found some information about #{query}. #{format_conversational_response(key_info, opts)}"
    end
  end

  defp format_conversational_response(key_info, _opts) do
    case length(key_info) do
      1 ->
        item = hd(key_info)
        "#{item.text} This came from #{format_source_citation(item)}."

      count when count <= 3 ->
        formatted_items =
          Enum.map(key_info, fn item ->
            "#{item.text}"
          end)

        Enum.join(formatted_items, " Additionally, ") <> "."

      _ ->
        "I found several relevant pieces of information. The most relevant results mention #{Enum.map(key_info, & &1.text) |> Enum.take(2) |> Enum.join(" and ")}."
    end
  end

  defp extract_sources(results) do
    Enum.map(results, fn result ->
      %{
        id: result.id,
        source: result.source,
        source_id: result.source_id,
        person: result.person_name || result.person_email,
        date: result.inserted_at,
        confidence: Map.get(result, :relevance_score, 0.0),
        citation: format_source_citation(result)
      }
    end)
  end

  defp calculate_overall_confidence(results) do
    if Enum.empty?(results) do
      0.0
    else
      confidence_scores =
        Enum.map(results, fn result ->
          Map.get(result, :relevance_score, 0.0) || Map.get(result, :similarity_score, 0.0) || 0.0
        end)

      # Weight by relevance (top results count more)
      weighted_scores =
        confidence_scores
        |> Enum.with_index()
        |> Enum.map(fn {score, index} ->
          # Decreasing weight
          weight = 1.0 - index * 0.1
          score * max(weight, 0.1)
        end)

      total_weight = Enum.sum(Enum.map(weighted_scores, fn _ -> 1.0 end))
      Enum.sum(weighted_scores) / total_weight
    end
  end

  defp total_mentions(mentions) do
    Enum.sum(Enum.map(mentions, fn {_person, person_mentions} -> length(person_mentions) end))
  end

  # Temporal answer building functions

  defp extract_temporal_information(results) do
    Enum.map(results, fn result ->
      %{
        text: result.text,
        date: result.inserted_at,
        source: result.source,
        person: result.person_name || result.person_email,
        temporal_markers: extract_temporal_markers(result.text)
      }
    end)
  end

  defp extract_temporal_markers(text) do
    # Extract dates, times, and temporal expressions
    patterns = [
      ~r/\b\d{1,2}\/\d{1,2}\/\d{4}\b/,
      ~r/\b\d{4}-\d{2}-\d{2}\b/,
      ~r/\b(?:Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday)\b/i,
      ~r/\b(?:January|February|March|April|May|June|July|August|September|October|November|December)\s+\d{1,2},?\s+\d{4}\b/i
    ]

    Enum.flat_map(patterns, fn pattern ->
      Regex.scan(pattern, text) |> Enum.map(&hd/1)
    end)
  end

  defp organize_temporal_info(temporal_info) do
    # Sort by date
    Enum.sort_by(temporal_info, & &1.date, DateTime)
  end

  defp format_temporal_answer(query, organized_info, opts) do
    include_citations = Keyword.get(opts, :include_citations, true)

    if Enum.empty?(organized_info) do
      "I couldn't find temporal information about #{query}."
    else
      time_grouped = group_by_time_period(organized_info)

      time_sections =
        Enum.map(time_grouped, fn {period, items} ->
          format_time_period(period, items, include_citations)
        end)

      "Here's the timeline for **#{query}**:\n\n" <> Enum.join(time_sections, "\n\n")
    end
  end

  defp group_by_time_period(temporal_info) do
    now = DateTime.utc_now()

    Enum.group_by(temporal_info, fn item ->
      days_diff = DateTime.diff(now, item.date, :day)

      cond do
        days_diff <= 7 -> "This Week"
        days_diff <= 30 -> "This Month"
        days_diff <= 90 -> "Last 3 Months"
        days_diff <= 365 -> "This Year"
        true -> "Previous Years"
      end
    end)
  end

  defp format_time_period(period, items, include_citations) do
    items_text =
      Enum.map(items, fn item ->
        date_str = Calendar.strftime(item.date, "%B %d, %Y")
        text = extract_relevant_snippet(item.text)

        if include_citations do
          "• **#{date_str}**: #{text} *(#{format_source_citation(item)})*"
        else
          "• **#{date_str}**: #{text}"
        end
      end)
      |> Enum.join("\n")

    "**#{period}:**\n#{items_text}"
  end

  defp determine_time_range(temporal_info) do
    if Enum.empty?(temporal_info) do
      nil
    else
      dates = Enum.map(temporal_info, & &1.date)
      earliest = Enum.min(dates)
      latest = Enum.max(dates)
      {earliest, latest}
    end
  end

  # Contact answer building functions

  defp extract_contact_information(results) do
    Enum.map(results, fn result ->
      %{
        text: result.text,
        source: result.source,
        person: result.person_name || result.person_email,
        email: result.person_email,
        date: result.inserted_at,
        contact_type: determine_contact_type(result)
      }
    end)
  end

  defp determine_contact_type(result) do
    cond do
      result.source == "hubspot" -> "CRM Contact"
      String.contains?(String.downcase(result.text), "client") -> "Client"
      String.contains?(String.downcase(result.text), "customer") -> "Customer"
      String.contains?(String.downcase(result.text), "colleague") -> "Colleague"
      true -> "Contact"
    end
  end

  defp organize_contact_info(contact_info) do
    # Group by person
    Enum.group_by(contact_info, fn item -> item.person end)
  end

  defp format_contact_answer(query, organized_contacts, opts) do
    include_citations = Keyword.get(opts, :include_citations, true)

    if Enum.empty?(organized_contacts) do
      "I couldn't find contact information related to #{query}."
    else
      contact_sections =
        Enum.map(organized_contacts, fn {person, items} ->
          format_contact_section(person, items, include_citations)
        end)

      "Here's the contact information for **#{query}**:\n\n" <>
        Enum.join(contact_sections, "\n\n")
    end
  end

  defp format_contact_section(person, items, include_citations) do
    contact_types = Enum.uniq(Enum.map(items, & &1.contact_type))
    latest_date = Enum.max_by(items, & &1.date)

    header = "**#{person}** (#{Enum.join(contact_types, ", ")})"

    recent_info =
      items
      |> Enum.filter(fn item -> DateTime.diff(latest_date.date, item.date, :day) <= 30 end)
      |> Enum.map(fn item ->
        text = extract_relevant_snippet(item.text)
        date_str = Calendar.strftime(item.date, "%B %d")

        if include_citations do
          "• #{text} *(#{date_str} - #{format_source_citation(item)})*"
        else
          "• #{text} *(#{date_str})*"
        end
      end)
      |> Enum.join("\n")

    if recent_info != "" do
      "#{header}\n#{recent_info}"
    else
      "#{header}\n• Limited recent information available"
    end
  end

  # Scheduling answer building functions

  defp extract_scheduling_information(results) do
    Enum.filter(results, fn result ->
      String.contains?(String.downcase(result.text), "meeting") or
        String.contains?(String.downcase(result.text), "schedule") or
        String.contains?(String.downcase(result.text), "call") or
        result.source == "calendar"
    end)
    |> Enum.map(fn result ->
      %{
        text: result.text,
        source: result.source,
        date: result.inserted_at,
        person: result.person_name || result.person_email,
        scheduling_info: extract_scheduling_details(result.text)
      }
    end)
  end

  defp extract_scheduling_details(text) do
    %{
      has_time: contains_time_reference?(text),
      has_people: contains_people_reference?(text),
      has_location: contains_location_reference?(text),
      urgency: determine_urgency(text)
    }
  end

  defp contains_time_reference?(text) do
    time_patterns = [
      ~r/\b\d{1,2}:\d{2}\s*(?:am|pm|AM|PM)\b/,
      ~r/\b(?:morning|afternoon|evening|noon|tonight)\b/i,
      ~r/\b(?:today|tomorrow|yesterday)\b/i
    ]

    Enum.any?(time_patterns, fn pattern -> Regex.match?(pattern, text) end)
  end

  defp contains_people_reference?(text) do
    person_pattern = ~r/\b[A-Z][a-z]+\s+[A-Z][a-z]+\b/
    Regex.match?(person_pattern, text)
  end

  defp contains_location_reference?(text) do
    location_indicators = ["office", "home", "zoom", "meet", "call", "conference room"]
    Enum.any?(location_indicators, &String.contains?(String.downcase(text), &1))
  end

  defp determine_urgency(text) do
    cond do
      String.contains?(String.downcase(text), "urgent") or
          String.contains?(String.downcase(text), "asap") ->
        :high

      String.contains?(String.downcase(text), "this week") ->
        :medium

      true ->
        :low
    end
  end

  defp analyze_scheduling_context(scheduling_info) do
    %{
      total_references: length(scheduling_info),
      time_sensitivity: calculate_time_sensitivity(scheduling_info),
      involved_people: extract_involved_people(scheduling_info),
      location_requirements: determine_location_requirements(scheduling_info),
      suggested_duration: suggest_meeting_duration(scheduling_info)
    }
  end

  defp calculate_time_sensitivity(scheduling_info) do
    urgency_levels = Enum.map(scheduling_info, & &1.scheduling_info.urgency)

    cond do
      Enum.any?(urgency_levels, &(&1 == :high)) -> :high
      Enum.any?(urgency_levels, &(&1 == :medium)) -> :medium
      true -> :low
    end
  end

  defp extract_involved_people(scheduling_info) do
    scheduling_info
    |> Enum.flat_map(fn item -> [item.person] end)
    |> Enum.uniq()
    |> Enum.filter(& &1)
  end

  defp determine_location_requirements(scheduling_info) do
    has_location_refs =
      Enum.any?(scheduling_info, fn item -> item.scheduling_info.has_location end)

    if has_location_refs do
      :required
    else
      :flexible
    end
  end

  defp suggest_meeting_duration(_scheduling_info) do
    # Default suggestion - could be enhanced based on context
    # minutes
    30
  end

  defp format_scheduling_answer(query, analysis, opts) do
    include_citations = Keyword.get(opts, :include_citations, true)

    base_answer =
      case analysis.time_sensitivity do
        :high ->
          "This appears to be time-sensitive. I recommend scheduling this as soon as possible."

        :medium ->
          "This should be scheduled within the next week."

        :low ->
          "This can be scheduled at your convenience."
      end

    people_info =
      if not Enum.empty?(analysis.involved_people) do
        "The people involved are: #{Enum.join(analysis.involved_people, ", ")}."
      else
        ""
      end

    location_info =
      case analysis.location_requirements do
        :required -> "A specific location or meeting setup appears to be required."
        :flexible -> "Location requirements appear to be flexible."
      end

    duration_info = "I suggest a #{analysis.suggested_duration}-minute meeting."

    answer_parts =
      [base_answer, people_info, location_info, duration_info]
      |> Enum.filter(&(&1 != ""))
      |> Enum.join(" ")

    "Based on the context for **#{query}**: #{answer_parts}"
  end

  defp generate_scheduling_suggestions(analysis) do
    [
      "Consider checking calendar availability for all involved parties",
      "Prepare an agenda if this is a formal meeting",
      case analysis.time_sensitivity do
        :high -> "Send calendar invites as soon as possible"
        _ -> "Send calendar invites at least 24 hours in advance"
      end
    ]
  end

  # Helper functions for no results answers

  defp generate_search_suggestions(query) do
    [
      "Try searching for related terms or synonyms",
      "Check if you're looking for a person, company, or topic",
      "Verify the spelling of names or technical terms",
      "Consider broadening your search terms"
    ]
  end

  defp format_suggestions(suggestions) do
    suggestions
    |> Enum.map(fn suggestion -> "• #{suggestion}" end)
    |> Enum.join("\n")
  end
end
