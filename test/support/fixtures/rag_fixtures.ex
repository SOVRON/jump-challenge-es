defmodule Jump.RAGFixtures do
  @moduledoc """
  Fixtures for RAG (Retrieval Augmented Generation) tests.
  """

  @doc """
  Generate a RAG chunk fixture
  """
  def rag_chunk_fixture(attrs \\ %{}) do
    attrs =
      Enum.into(attrs, %{
        "id" => "chunk_#{:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)}",
        "text" => "This is a sample chunk of text for RAG retrieval",
        "source" => "email",
        "source_id" => "msg_123",
        "person_name" => "John Doe",
        "person_email" => "john@example.com",
        "embedding" => generate_embedding(),
        "similarity_score" => 0.85,
        "relevance_score" => 0.9,
        "inserted_at" => DateTime.utc_now(),
        "metadata" => %{
          "subject" => "Test subject",
          "date" => DateTime.to_string(DateTime.utc_now())
        }
      })

    %{
      "id" => attrs["id"],
      "text" => attrs["text"],
      "source" => attrs["source"],
      "source_id" => attrs["source_id"],
      "person_name" => attrs["person_name"],
      "person_email" => attrs["person_email"],
      "embedding" => attrs["embedding"],
      "similarity_score" => attrs["similarity_score"],
      "relevance_score" => attrs["relevance_score"],
      "inserted_at" => attrs["inserted_at"],
      "metadata" => attrs["metadata"]
    }
  end

  @doc """
  Generate a search result fixture
  """
  def search_result_fixture(attrs \\ %{}) do
    chunk = rag_chunk_fixture(attrs)

    %{
      "id" => chunk["id"],
      "text" => chunk["text"],
      "source" => chunk["source"],
      "source_id" => chunk["source_id"],
      "person_name" => chunk["person_name"],
      "person_email" => chunk["person_email"],
      "similarity_score" => chunk["similarity_score"],
      "rank" => Map.get(attrs, :rank, 1),
      "date" => chunk["inserted_at"]
    }
  end

  @doc """
  Generate answer builder context fixture
  """
  def answer_context_fixture(attrs \\ %{}) do
    results = Map.get(attrs, :results, [search_result_fixture()])

    %{
      "query" => Map.get(attrs, :query, "What is discussed?"),
      "results" => results,
      "result_count" => length(results),
      "timestamp" => DateTime.utc_now(),
      "style" => Map.get(attrs, :style, :comprehensive),
      "include_citations" => Map.get(attrs, :include_citations, true)
    }
  end

  @doc """
  Generate a built answer fixture
  """
  def answer_fixture(attrs \\ %{}) do
    %{
      "answer" => Map.get(attrs, :answer, "This is a test answer based on the context provided."),
      "confidence" => Map.get(attrs, :confidence, 0.92),
      "style" => Map.get(attrs, :style, :comprehensive),
      "sources" =>
        Map.get(attrs, :sources, [
          %{
            "id" => "chunk_1",
            "text" => "Source text 1",
            "relevance" => 0.95
          }
        ]),
      "citations" =>
        Map.get(attrs, :citations, [
          %{
            "id" => "chunk_1",
            "quote" => "relevant quote",
            "position" => 1
          }
        ]),
      "generated_at" => DateTime.utc_now()
    }
  end

  @doc """
  Generate embedding vector (simplified - real embeddings are 1536+ dims)
  """
  def generate_embedding(size \\ 10) do
    List.duplicate(0.1, size)
  end

  @doc """
  Generate temporal query fixture
  """
  def temporal_query_fixture(attrs \\ %{}) do
    now = DateTime.utc_now()
    start_date = Map.get(attrs, :start_date, DateTime.add(now, -7 * 86400))
    end_date = Map.get(attrs, :end_date, now)

    %{
      "query" => Map.get(attrs, :query, "What happened this week?"),
      "time_range" => "this_week",
      "start_date" => start_date,
      "end_date" => end_date,
      "intent" => :temporal_search
    }
  end

  @doc """
  Generate entity search fixture
  """
  def entity_search_fixture(entity_type \\ :person, attrs \\ %{}) do
    %{
      "entity_type" => entity_type,
      "entity_name" => Map.get(attrs, :entity_name, "John Doe"),
      "entity_email" => Map.get(attrs, :entity_email, "john@example.com"),
      "search_results" => Map.get(attrs, :results, [search_result_fixture()]),
      "match_count" => Map.get(attrs, :match_count, 5)
    }
  end
end
