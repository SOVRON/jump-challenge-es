defmodule Jump.RAG do
  @moduledoc """
  The RAG context handles retrieval-augmented generation with vector search, intelligent retrieval, and answer construction.
  """

  import Ecto.Query, warn: false
  alias Jump.Repo

  alias Jump.RAG.{Chunk, Search, Retriever, AnswerBuilder, Tools}

  def list_chunks(user_id) do
    Chunk
    |> where([c], c.user_id == ^user_id)
    |> order_by([c], desc: c.inserted_at)
    |> Repo.all()
  end

  def get_chunk!(id), do: Repo.get!(Chunk, id)

  def create_chunk(attrs \\ %{}) do
    %Chunk{}
    |> Chunk.changeset(attrs)
    |> Repo.insert()
  end

  def update_chunk(%Chunk{} = chunk, attrs) do
    chunk
    |> Chunk.changeset(attrs)
    |> Repo.update()
  end

  def delete_chunk(%Chunk{} = chunk) do
    Repo.delete(chunk)
  end

  def change_chunk(%Chunk{} = chunk, attrs \\ %{}) do
    Chunk.changeset(chunk, attrs)
  end

  def create_chunk_with_embedding(
        user_id,
        source,
        source_id,
        text,
        embedding,
        meta \\ %{},
        person_email \\ nil,
        person_name \\ nil
      ) do
    create_chunk(%{
      user_id: user_id,
      source: source,
      source_id: source_id,
      text: text,
      embedding: embedding,
      meta: meta,
      person_email: person_email,
      person_name: person_name
    })
  end

  def search_similar_chunks(user_id, query_embedding, limit \\ 15, filters \\ %{}) do
    base_query =
      Chunk
      |> where([c], c.user_id == ^user_id)

    # Apply filters
    filtered_query =
      Enum.reduce(filters, base_query, fn {key, value}, query ->
        case key do
          :source ->
            where(query, [c], c.source == ^value)

          :person_email ->
            where(query, [c], c.person_email == ^value)

          :recency_days ->
            cutoff_date = DateTime.add(DateTime.utc_now(), -value * 24 * 60 * 60, :second)
            where(query, [c], c.inserted_at >= ^cutoff_date)

          _ ->
            query
        end
      end)

    # Perform vector similarity search
    filtered_query
    |> order_by([c], fragment("? <=> ?", c.embedding, ^query_embedding))
    |> limit(^limit)
    |> Repo.all()
  end

  def get_chunks_by_source(user_id, source) do
    Chunk
    |> where([c], c.user_id == ^user_id and c.source == ^source)
    |> order_by([c], desc: c.inserted_at)
    |> Repo.all()
  end

  def get_chunks_by_person(user_id, person_email) do
    Chunk
    |> where([c], c.user_id == ^user_id and c.person_email == ^person_email)
    |> order_by([c], desc: c.inserted_at)
    |> Repo.all()
  end

  def get_chunks_by_source_id(user_id, source, source_id) do
    Chunk
    |> where([c], c.user_id == ^user_id and c.source == ^source and c.source_id == ^source_id)
    |> Repo.all()
  end

  def update_chunk_embedding(chunk_id, embedding) do
    get_chunk!(chunk_id)
    |> update_chunk(%{embedding: embedding})
  end

  def delete_chunks_by_source_id(user_id, source, source_id) do
    Chunk
    |> where([c], c.user_id == ^user_id and c.source == ^source and c.source_id == ^source_id)
    |> Repo.delete_all()
  end

  # RAG Search and Retrieval Functions

  @doc """
  Perform intelligent RAG search with context-aware retrieval.
  """
  def search(user_id, query, opts \\ []) do
    Retriever.retrieve_context(user_id, query, opts)
  end

  @doc """
  Search with conversation history for multi-turn queries.
  """
  def search_with_history(user_id, query, conversation_history, opts \\ []) do
    Retriever.retrieve_with_history(user_id, query, conversation_history, opts)
  end

  @doc """
  Build an answer from search results.
  """
  def build_answer(query, context_results, opts \\ []) do
    AnswerBuilder.build_answer(query, context_results, opts)
  end

  # Specialized Search Functions

  @doc """
  Search for person-related information.
  """
  def search_person(user_id, person_identifier, opts \\ []) do
    Search.person_search(user_id, person_identifier, opts)
  end

  @doc """
  Search for "who mentioned X" type queries.
  """
  def find_mentions(user_id, mention_target, opts \\ []) do
    Search.pattern_search(user_id, "who_mentioned", mention_target, opts)
  end

  @doc """
  Search temporal information (when questions).
  """
  def search_temporal(user_id, query, time_range, opts \\ []) do
    Search.temporal_search(user_id, query, time_range.start_date, time_range.end_date, opts)
  end

  @doc """
  Search for scheduling-related information.
  """
  def search_scheduling_context(user_id, participants, opts \\ []) do
    Retriever.retrieve_scheduling_context(user_id, participants, opts)
  end

  # LangChain Tool Integration

  @doc """
  Get all available RAG tools for LangChain integration.
  """
  def get_langchain_tools() do
    [
      Tools.create_rag_search_tool(),
      Tools.create_find_people_tool(),
      Tools.create_search_emails_tool(),
      Tools.create_search_calendar_tool(),
      Tools.create_find_mentions_tool(),
      Tools.create_when_search_tool()
    ]
  end

  @doc """
  Execute a specific RAG tool.
  """
  def execute_tool(tool_name, user_id, args) do
    case tool_name do
      "search_rag" -> Tools.execute_rag_search(user_id, args)
      "find_people" -> Tools.execute_find_people(user_id, args)
      "search_emails" -> Tools.execute_search_emails(user_id, args)
      "search_calendar" -> Tools.execute_search_calendar(user_id, args)
      "find_mentions" -> Tools.execute_find_mentions(user_id, args)
      "when_search" -> Tools.execute_when_search(user_id, args)
      _ -> {:error, :unknown_tool}
    end
  end

  # Utility Functions

  @doc """
  Generate embedding for search queries.
  """
  def generate_query_embedding(query_text) do
    # This would integrate with the embedding generation system
    # For now, return a placeholder
    {:ok, List.duplicate(0.1, 1536)}
  end

  @doc """
  Get statistics about RAG data for a user.
  """
  def get_user_statistics(user_id) do
    total_chunks =
      Chunk
      |> where([c], c.user_id == ^user_id)
      |> Repo.aggregate(:count)

    chunks_by_source =
      Chunk
      |> where([c], c.user_id == ^user_id)
      |> group_by([c], c.source)
      |> select([c], {c.source, count(c.id)})
      |> Repo.all()
      |> Enum.into(%{})

    recent_chunks =
      Chunk
      |> where([c], c.user_id == ^user_id)
      |> where(
        [c],
        c.inserted_at >= ^DateTime.add(DateTime.utc_now(), -7 * 24 * 60 * 60, :second)
      )
      |> Repo.aggregate(:count)

    unique_people =
      Chunk
      |> where([c], c.user_id == ^user_id)
      |> where([c], not is_nil(c.person_email))
      |> select([c], c.person_email)
      |> distinct(true)
      |> Repo.all()
      |> length()

    %{
      total_chunks: total_chunks,
      chunks_by_source: chunks_by_source,
      recent_chunks: recent_chunks,
      unique_people: unique_people,
      last_updated: DateTime.utc_now()
    }
  end
end
