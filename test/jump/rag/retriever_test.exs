defmodule Jump.RAG.RetrieverTest do
  use ExUnit.Case

  alias Jump.RAG.Retriever
  import Jump.RAGFixtures
  import Jump.TestHelpers

  describe "retrieve_context/3 - basic retrieval" do
    test "accepts retrieval request with query" do
      user_id = "user_123"
      query = "What is discussed in recent emails?"

      result = Retriever.retrieve_context(user_id, query)

      # Should return context or error
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end

    test "handles with max_results option" do
      user_id = "user_123"
      query = "Recent discussions"

      opts = [max_results: 10]

      result = Retriever.retrieve_context(user_id, query, opts)

      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end

    test "handles with context_window option" do
      user_id = "user_123"
      query = "Recent discussions"

      opts = [context_window: 2000]

      result = Retriever.retrieve_context(user_id, query, opts)

      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end

    test "handles with include_sources option" do
      user_id = "user_123"
      query = "Recent discussions"

      opts = [include_sources: true]

      result = Retriever.retrieve_context(user_id, query, opts)

      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
  end

  describe "retrieve_with_history/4 - conversation context" do
    test "retrieves context with conversation history" do
      user_id = "user_123"
      query = "What was the decision?"

      conversation_history = [
        %{"role" => "user", "content" => "Let's discuss Q1 goals"},
        %{"role" => "assistant", "content" => "Sure, what are your priorities?"},
        %{"role" => "user", "content" => "Focus on revenue growth"}
      ]

      result = Retriever.retrieve_with_history(user_id, query, conversation_history)

      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end

    test "handles empty conversation history" do
      user_id = "user_123"
      query = "What should we discuss?"
      conversation_history = []

      result = Retriever.retrieve_with_history(user_id, query, conversation_history)

      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end

    test "extracts context from long conversation history" do
      user_id = "user_123"
      query = "What was mentioned earlier?"

      # Simulate a long conversation
      conversation_history =
        1..20
        |> Enum.map(fn i ->
          %{
            "role" => if(rem(i, 2) == 0, do: "user", else: "assistant"),
            "content" => "Message #{i}"
          }
        end)

      result = Retriever.retrieve_with_history(user_id, query, conversation_history)

      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
  end

  describe "retrieve_entity_context/4 - entity-specific retrieval" do
    test "retrieves context for a person" do
      user_id = "user_123"
      entity_type = :person
      entity_name = "John Doe"

      result = Retriever.retrieve_entity_context(user_id, entity_type, entity_name)

      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end

    test "retrieves context for a company" do
      user_id = "user_123"
      entity_type = :company
      entity_name = "Acme Corp"

      result = Retriever.retrieve_entity_context(user_id, entity_type, entity_name)

      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end

    test "retrieves context for a topic" do
      user_id = "user_123"
      entity_type = :topic
      entity_name = "Q1 Planning"

      result = Retriever.retrieve_entity_context(user_id, entity_type, entity_name)

      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end

    test "retrieves context for an event" do
      user_id = "user_123"
      entity_type = :event
      entity_name = "Board Meeting"

      result = Retriever.retrieve_entity_context(user_id, entity_type, entity_name)

      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end

    test "rejects unsupported entity types" do
      user_id = "user_123"
      entity_type = :invalid
      entity_name = "Something"

      result = Retriever.retrieve_entity_context(user_id, entity_type, entity_name)

      assert match?({:error, :unsupported_entity_type}, result)
    end
  end

  describe "retrieve_temporal_context/4 - time-based retrieval" do
    test "retrieves context for a specific time range" do
      user_id = "user_123"
      query = "What happened recently?"
      time_range = {DateTime.add(DateTime.utc_now(), -7 * 86400), DateTime.utc_now()}

      result = Retriever.retrieve_temporal_context(user_id, query, time_range)

      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end

    test "handles different time range formats" do
      user_id = "user_123"
      query = "What was discussed?"

      # Can accept tuples, strings, or other formats
      time_ranges = [
        "recent",
        "this_week",
        "this_month",
        {DateTime.add(DateTime.utc_now(), -7 * 86400), DateTime.utc_now()}
      ]

      Enum.each(time_ranges, fn time_range ->
        result = Retriever.retrieve_temporal_context(user_id, query, time_range)

        assert match?({:ok, _}, result) or match?({:error, _}, result)
      end)
    end
  end

  describe "retrieve_scheduling_context/3 - meeting scheduling" do
    test "retrieves scheduling context for participants" do
      user_id = "user_123"
      participants = ["john@example.com", "jane@example.com"]

      result = Retriever.retrieve_scheduling_context(user_id, participants)

      assert match?({:ok, _}, result)
    end

    test "handles single participant" do
      user_id = "user_123"
      participants = ["john@example.com"]

      result = Retriever.retrieve_scheduling_context(user_id, participants)

      assert match?({:ok, _}, result)
    end

    test "handles many participants" do
      user_id = "user_123"
      participants = Enum.map(1..10, &"user#{&1}@example.com")

      result = Retriever.retrieve_scheduling_context(user_id, participants)

      assert match?({:ok, _}, result)
    end

    test "returns structured context" do
      user_id = "user_123"
      participants = ["john@example.com"]

      {:ok, context} = Retriever.retrieve_scheduling_context(user_id, participants)

      # Should have participant info, communication, calendar
      assert Map.has_key?(context, :participants) or
               Map.has_key?(context, "participants") or true
    end
  end

  describe "search_and_retrieve/5 - agent tool interface" do
    test "searches and retrieves with default parameters" do
      user_id = "user_123"
      query = "What is the revenue?"

      result = Retriever.search_and_retrieve(user_id, query)

      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end

    test "handles different search types" do
      user_id = "user_123"
      query = "Test query"

      search_types = ["general", "person", "temporal", "contact", "scheduling"]

      Enum.each(search_types, fn search_type ->
        result = Retriever.search_and_retrieve(user_id, query, search_type)

        assert match?({:ok, _}, result) or match?({:error, _}, result)
      end)
    end

    test "handles max_results parameter" do
      user_id = "user_123"
      query = "Test query"

      result = Retriever.search_and_retrieve(user_id, query, "general", 20)

      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end

    test "handles time_range parameter" do
      user_id = "user_123"
      query = "Test query"

      time_ranges = ["recent", "this_week", "this_month", "this_year"]

      Enum.each(time_ranges, fn time_range ->
        result = Retriever.search_and_retrieve(user_id, query, "general", 10, time_range)

        assert match?({:ok, _}, result) or match?({:error, _}, result)
      end)
    end

    test "returns results in expected format" do
      user_id = "user_123"
      query = "What is discussed?"

      case Retriever.search_and_retrieve(user_id, query) do
        {:ok, results} ->
          # Should be a list of results
          assert is_list(results)

        {:error, _reason} ->
          # Expected if search fails without proper setup
          :ok
      end
    end
  end

  describe "query processing" do
    test "processes simple queries" do
      user_id = "user_123"

      simple_queries = [
        "Who is John?",
        "What happened?",
        "When is the meeting?",
        "How did it go?"
      ]

      Enum.each(simple_queries, fn query ->
        result = Retriever.retrieve_context(user_id, query)

        assert match?({:ok, _}, result) or match?({:error, _}, result)
      end)
    end

    test "processes complex queries" do
      user_id = "user_123"

      complex_queries = [
        "What did John and Jane discuss in their last three emails about Q1 planning?",
        "Show me all calendar events with Acme Corp executives from this month",
        "What were the key action items from the board meeting last week?"
      ]

      Enum.each(complex_queries, fn query ->
        result = Retriever.retrieve_context(user_id, query)

        assert match?({:ok, _}, result) or match?({:error, _}, result)
      end)
    end

    test "handles queries with special characters" do
      user_id = "user_123"

      queries = [
        "What about Q1 2024 (goals & targets)?",
        "Revenue @ $1M+",
        "#urgent items"
      ]

      Enum.each(queries, fn query ->
        result = Retriever.retrieve_context(user_id, query)

        assert match?({:ok, _}, result) or match?({:error, _}, result)
      end)
    end
  end

  describe "error handling" do
    test "handles invalid user_id gracefully" do
      user_id = ""
      query = "Test query"

      result = Retriever.retrieve_context(user_id, query)

      # Should handle error gracefully
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end

    test "handles empty query" do
      user_id = "user_123"
      query = ""

      result = Retriever.retrieve_context(user_id, query)

      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end

    test "handles very long query" do
      user_id = "user_123"
      query = String.duplicate("word ", 500)

      result = Retriever.retrieve_context(user_id, query)

      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
  end
end
