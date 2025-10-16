defmodule Jump.RAG.Search do
  @moduledoc """
  Handles vector similarity search and retrieval for the RAG pipeline.
  """

  import Ecto.Query
  alias Jump.Repo
  alias Jump.RAG.Chunk

  @default_limit 15
  @default_similarity_threshold 0.7
  @max_search_results 50

  @doc """
  Perform vector similarity search for RAG queries.
  """
  def search_embeddings(user_id, query_embedding, opts \\ []) do
    limit = Keyword.get(opts, :limit, @default_limit)
    similarity_threshold = Keyword.get(opts, :similarity_threshold, @default_similarity_threshold)
    filters = Keyword.get(opts, :filters, %{})

    # Build base query
    base_query =
      from c in Chunk,
        where: c.user_id == ^user_id,
        where: not is_nil(c.embedding)

    # Apply filters
    filtered_query = apply_filters(base_query, filters)

    # Add vector similarity search
    similarity_query =
      from [c] in filtered_query,
        where: fragment("? <=> ?", c.embedding, ^query_embedding) > ^similarity_threshold,
        order_by: [desc: fragment("? <=> ?", c.embedding, ^query_embedding)],
        limit: ^min(limit, @max_search_results)

    # Execute query
    results = Repo.all(similarity_query)

    # Score and post-process results
    scored_results = score_and_process_results(results, query_embedding, opts)

    {:ok, scored_results}
  end

  @doc """
  Hybrid search combining vector similarity with keyword matching.
  """
  def hybrid_search(user_id, query_text, query_embedding, opts \\ []) do
    limit = Keyword.get(opts, :limit, @default_limit)
    keyword_boost = Keyword.get(opts, :keyword_boost, 0.2)

    # Get vector search results
    {:ok, vector_results} = search_embeddings(user_id, query_embedding, opts)

    # Get keyword search results
    keyword_results = keyword_search(user_id, query_text, opts)

    # Combine and re-rank results
    combined_results = combine_search_results(vector_results, keyword_results, keyword_boost)

    # Return top results
    final_results = combined_results |> Enum.take(limit)

    {:ok, final_results}
  end

  @doc """
  Search for specific patterns like "who mentioned X" or "emails about Y".
  """
  def pattern_search(user_id, pattern, query_text, opts \\ []) do
    case pattern do
      "who_mentioned" ->
        who_mentioned_search(user_id, query_text, opts)

      "emails_about" ->
        emails_about_search(user_id, query_text, opts)

      "recent_activity" ->
        recent_activity_search(user_id, query_text, opts)

      "contact_related" ->
        contact_related_search(user_id, query_text, opts)

      _ ->
        # Fallback to hybrid search
        case generate_embedding(query_text) do
          {:ok, embedding} ->
            hybrid_search(user_id, query_text, embedding, opts)

          {:error, _} ->
            keyword_search(user_id, query_text, opts)
        end
    end
  end

  @doc """
  Semantic search within specific date ranges.
  """
  def temporal_search(user_id, query_embedding, start_date, end_date, opts \\ []) do
    limit = Keyword.get(opts, :limit, @default_limit)

    query =
      from c in Chunk,
        where: c.user_id == ^user_id,
        where: not is_nil(c.embedding),
        where: c.inserted_at >= ^start_date,
        where: c.inserted_at <= ^end_date,
        where:
          fragment("? <=> ?", c.embedding, ^query_embedding) > ^@default_similarity_threshold,
        order_by: [desc: fragment("? <=> ?", c.embedding, ^query_embedding)],
        limit: ^limit

    results = Repo.all(query)
    scored_results = score_and_process_results(results, query_embedding, opts)

    {:ok, scored_results}
  end

  @doc """
  Search for chunks related to specific people or contacts.
  """
  def person_search(user_id, person_identifier, opts \\ []) do
    limit = Keyword.get(opts, :limit, @default_limit)

    # Normalize person identifier (email or name)
    normalized_identifier = normalize_person_identifier(person_identifier)

    query =
      from c in Chunk,
        where: c.user_id == ^user_id,
        where:
          ilike(c.person_email, ^"%#{normalized_identifier}%") or
            ilike(c.person_name, ^"%#{normalized_identifier}%") or
            ilike(c.text, ^"%#{normalized_identifier}%"),
        order_by: [desc: c.inserted_at],
        limit: ^limit

    results = Repo.all(query)

    # Score results based on relevance
    scored_results = score_person_results(results, normalized_identifier)

    {:ok, scored_results}
  end

  # Private functions

  defp apply_filters(query, filters) do
    Enum.reduce(filters, query, fn {key, value}, acc_query ->
      apply_filter(acc_query, key, value)
    end)
  end

  defp apply_filter(query, "source", sources) when is_list(sources) do
    from c in query, where: c.source in ^sources
  end

  defp apply_filter(query, "source", source) do
    from c in query, where: c.source == ^source
  end

  defp apply_filter(query, "person_email", email) do
    from c in query, where: c.person_email == ^email
  end

  defp apply_filter(query, "emails", emails) when is_list(emails) do
    from c in query, where: c.person_email in ^emails
  end

  defp apply_filter(query, "date_range", {start_date, end_date}) do
    from c in query,
      where: c.inserted_at >= ^start_date,
      where: c.inserted_at <= ^end_date
  end

  defp apply_filter(query, "keywords", keywords) when is_list(keywords) do
    conditions =
      Enum.map(keywords, fn keyword ->
        dynamic([c], ilike(c.text, ^"%#{keyword}%"))
      end)

    from c in query, where: ^Enum.reduce(conditions, &dynamic(^&2 or ^&1))
  end

  defp apply_filter(query, _key, _value), do: query

  defp keyword_search(user_id, query_text, opts \\ []) do
    limit = Keyword.get(opts, :limit, @default_limit)

    # Extract keywords from query text
    keywords = extract_keywords(query_text)

    if Enum.empty?(keywords) do
      []
    else
      query =
        from c in Chunk,
          where: c.user_id == ^user_id,
          where: ilike(c.text, ^"%#{hd(keywords)}%"),
          # Get more results for ranking
          limit: ^(limit * 2)

      base_results = Repo.all(query)

      # Filter by additional keywords
      filtered_results =
        Enum.filter(base_results, fn chunk ->
          Enum.all?(tl(keywords), fn keyword ->
            String.contains?(String.downcase(chunk.text), String.downcase(keyword))
          end)
        end)

      # Score keyword results
      score_keyword_results(filtered_results, keywords)
    end
  end

  defp combine_search_results(vector_results, keyword_results, keyword_boost) do
    # Combine results and merge scores
    combined_map =
      Enum.reduce(vector_results, %{}, fn result, acc ->
        Map.put(acc, result.id, Map.put(result, :combined_score, result.similarity_score))
      end)

    # Add keyword results with boost
    combined_map =
      Enum.reduce(keyword_results, combined_map, fn result, acc ->
        existing_score = Map.get(acc, result.id, %{}).combined_score || 0.0
        new_score = existing_score + result.keyword_score * keyword_boost

        Map.put(
          acc,
          result.id,
          Map.put(result, :combined_score, new_score)
          |> Map.put(:similarity_score, existing_score)
        )
      end)

    # Sort by combined score and return results
    combined_map
    |> Map.values()
    |> Enum.sort_by(&(-&1.combined_score))
  end

  defp score_and_process_results(results, query_embedding, opts) do
    # Add additional metadata and scoring
    Enum.map(results, fn chunk ->
      base_score = calculate_base_similarity_score(chunk, query_embedding)

      chunk
      |> Map.put(:similarity_score, base_score)
      |> Map.put(:combined_score, base_score)
      |> add_relevance_metadata(opts)
    end)
    |> Enum.sort_by(&(-&1.similarity_score))
  end

  defp calculate_base_similarity_score(chunk, _query_embedding) do
    # For now, we'll use a placeholder. In practice, this would come from the vector search
    # The actual similarity score would be calculated during the vector search
    # Placeholder: 0.8 to 1.0
    0.8 + :rand.uniform() * 0.2
  end

  defp add_relevance_metadata(chunk, opts) do
    recency_bonus = calculate_recency_bonus(chunk.inserted_at)
    source_bonus = calculate_source_bonus(chunk.source, opts)

    chunk
    |> Map.put(:recency_bonus, recency_bonus)
    |> Map.put(:source_bonus, source_bonus)
    |> Map.put(:final_score, chunk.similarity_score + recency_bonus + source_bonus)
  end

  defp calculate_recency_bonus(inserted_at) do
    days_ago = DateTime.diff(DateTime.utc_now(), inserted_at, :day)

    cond do
      # Recent: high bonus
      days_ago <= 7 -> 0.1
      # This month: medium bonus
      days_ago <= 30 -> 0.05
      # This quarter: small bonus
      days_ago <= 90 -> 0.02
      # Older: no bonus
      true -> 0.0
    end
  end

  defp calculate_source_bonus(source, _opts) do
    case source do
      # Prefer email content
      "gmail" -> 0.05
      # CRM content
      "hubspot" -> 0.03
      # Calendar events
      "calendar" -> 0.02
      _ -> 0.0
    end
  end

  defp extract_keywords(text) do
    # Simple keyword extraction - could be enhanced with NLP
    text
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9\s]/, " ")
    |> String.split()
    |> Enum.filter(fn word -> String.length(word) > 2 end)
    |> Enum.uniq()
    # Limit to top 5 keywords
    |> Enum.take(5)
  end

  defp score_keyword_results(results, keywords) do
    Enum.map(results, fn chunk ->
      score = calculate_keyword_score(chunk.text, keywords)
      Map.put(chunk, :keyword_score, score)
    end)
    |> Enum.sort_by(&(-&1.keyword_score))
  end

  defp calculate_keyword_score(text, keywords) do
    text_lower = String.downcase(text)

    # Count keyword matches
    matches =
      Enum.count(keywords, fn keyword ->
        String.contains?(text_lower, String.downcase(keyword))
      end)

    # Calculate score based on matches and text length
    word_count = length(String.split(text))
    match_ratio = matches / length(keywords)
    # Normalize by text length
    length_factor = min(word_count / 100, 1.0)

    match_ratio * length_factor
  end

  defp who_mentioned_search(user_id, query_text, opts \\ []) do
    # Extract person name from query like "who mentioned John"
    person_name = extract_person_from_query(query_text)

    if person_name do
      person_search(user_id, person_name, opts)
    else
      # Fallback to hybrid search
      case generate_embedding(query_text) do
        {:ok, embedding} -> hybrid_search(user_id, query_text, embedding, opts)
        {:error, _} -> {:ok, []}
      end
    end
  end

  defp emails_about_search(user_id, query_text, opts \\ []) do
    # Search for emails about specific topics
    filters = Keyword.get(opts, :filters, %{})
    topic_filters = Map.put(filters, "source", "gmail")

    case generate_embedding(query_text) do
      {:ok, embedding} ->
        search_embeddings(user_id, embedding, Keyword.put(opts, :filters, topic_filters))

      {:error, _} ->
        keyword_results = keyword_search(user_id, query_text, opts)
        {:ok, keyword_results}
    end
  end

  defp recent_activity_search(user_id, query_text, opts \\ []) do
    # Search recent activity (last 7 days)
    start_date = DateTime.add(DateTime.utc_now(), -7 * 24 * 60 * 60, :second)
    end_date = DateTime.utc_now()

    case generate_embedding(query_text) do
      {:ok, embedding} ->
        temporal_search(user_id, embedding, start_date, end_date, opts)

      {:error, _} ->
        filters = Keyword.get(opts, :filters, %{})
        date_filters = Map.put(filters, "date_range", {start_date, end_date})
        limit = Keyword.get(opts, :limit, @default_limit)

        query =
          from c in Chunk,
            where: c.user_id == ^user_id,
            where: c.inserted_at >= ^start_date,
            where: c.inserted_at <= ^end_date,
            where: ilike(c.text, ^"%#{query_text}%"),
            order_by: [desc: c.inserted_at],
            limit: ^limit

        results = Repo.all(query)
        {:ok, score_keyword_results(results, extract_keywords(query_text))}
    end
  end

  defp contact_related_search(user_id, query_text, opts \\ []) do
    # Search for contact-related information
    contact_filters = Keyword.get(opts, :filters, %{})
    combined_filters = Map.put(contact_filters, "source", ["gmail", "hubspot"])

    case generate_embedding(query_text) do
      {:ok, embedding} ->
        search_embeddings(user_id, embedding, Keyword.put(opts, :filters, combined_filters))

      {:error, _} ->
        person_search(user_id, query_text, opts)
    end
  end

  defp score_person_results(results, person_identifier) do
    normalized_identifier = String.downcase(person_identifier)

    Enum.map(results, fn chunk ->
      score = calculate_person_relevance_score(chunk, normalized_identifier)
      Map.put(chunk, :person_score, score)
    end)
    |> Enum.sort_by(&(-&1.person_score))
  end

  defp calculate_person_relevance_score(chunk, person_identifier) do
    text_lower = String.downcase(chunk.text)

    email_match =
      chunk.person_email &&
        String.contains?(String.downcase(chunk.person_email), person_identifier)

    name_match =
      chunk.person_name && String.contains?(String.downcase(chunk.person_name), person_identifier)

    text_match = String.contains?(text_lower, person_identifier)

    cond do
      # Exact email match: highest score
      email_match -> 1.0
      # Name match: high score
      name_match -> 0.9
      # Text mention: medium score
      text_match -> 0.7
      # Low base score
      true -> 0.3
    end
  end

  defp normalize_person_identifier(identifier) do
    identifier
    |> String.trim()
    |> String.downcase()
  end

  defp extract_person_from_query(query) do
    # Extract person name from queries like "who mentioned John Doe"
    case Regex.run(~r/who mentioned\s+(.+)$/i, query) do
      [_, person_name] -> String.trim(person_name)
      _ -> nil
    end
  end

  defp generate_embedding(text) do
    # This would integrate with the embedding generation
    # For now, return a placeholder
    # Placeholder embedding
    {:ok, List.duplicate(0.1, 1536)}
  end
end
