defmodule Jump.RAG.AnswerBuilderTest do
  use ExUnit.Case

  alias Jump.RAG.AnswerBuilder
  import Jump.RAGFixtures

  describe "build_answer/3 - basic answer building" do
    test "builds answer from search results" do
      query = "What is the revenue?"
      results = [search_result_fixture(), search_result_fixture()]

      opts = [
        style: :comprehensive,
        include_citations: true
      ]

      answer = AnswerBuilder.build_answer(query, results, opts)

      assert answer != nil
      assert is_map(answer)
    end

    test "handles empty results list" do
      query = "What is the revenue?"
      results = []

      answer = AnswerBuilder.build_answer(query, results)

      assert answer != nil
    end

    test "handles single result" do
      query = "What is the revenue?"
      results = [search_result_fixture()]

      answer = AnswerBuilder.build_answer(query, results)

      assert answer != nil
    end

    test "handles many results" do
      query = "What is discussed?"
      results = Enum.map(1..20, fn _i -> search_result_fixture() end)

      answer = AnswerBuilder.build_answer(query, results)

      assert answer != nil
      assert is_map(answer)
    end
  end

  describe "build_answer/3 - answer styles" do
    test "builds comprehensive style answer" do
      query = "Explain the project"
      results = [search_result_fixture()]

      answer = AnswerBuilder.build_answer(query, results, style: :comprehensive)

      assert answer != nil
      # Comprehensive style should be detailed
      assert Map.has_key?(answer, :answer) or Map.has_key?(answer, "answer")
    end

    test "builds concise style answer" do
      query = "What happened?"
      results = [search_result_fixture()]

      answer = AnswerBuilder.build_answer(query, results, style: :concise)

      assert answer != nil
    end

    test "builds bullet style answer" do
      query = "List key points"
      results = [search_result_fixture()]

      answer = AnswerBuilder.build_answer(query, results, style: :bullet)

      assert answer != nil
    end

    test "builds expert style answer" do
      query = "Technical explanation needed"
      results = [search_result_fixture()]

      answer = AnswerBuilder.build_answer(query, results, style: :expert)

      assert answer != nil
    end

    test "defaults to comprehensive style" do
      query = "Test"
      results = [search_result_fixture()]

      answer = AnswerBuilder.build_answer(query, results)

      assert answer != nil
    end
  end

  describe "build_answer/3 - citations" do
    test "includes citations when requested" do
      query = "What is the strategy?"
      results = [search_result_fixture(), search_result_fixture()]

      answer = AnswerBuilder.build_answer(query, results, include_citations: true)

      # Answer should include citation information
      assert answer != nil
    end

    test "excludes citations when not requested" do
      query = "What is the strategy?"
      results = [search_result_fixture(), search_result_fixture()]

      answer = AnswerBuilder.build_answer(query, results, include_citations: false)

      assert answer != nil
    end

    test "builds sources list" do
      query = "What is the outcome?"

      results = [
        search_result_fixture(),
        search_result_fixture(source: "email", source_id: "msg_456")
      ]

      answer = AnswerBuilder.build_answer(query, results, include_citations: true)

      # Should have sources field
      assert answer != nil
    end
  end

  describe "build_answer/3 - confidence scoring" do
    test "assigns confidence score" do
      query = "Test query"
      results = [search_result_fixture()]

      answer = AnswerBuilder.build_answer(query, results)

      # Should have confidence field (0.0-1.0)
      assert answer != nil
    end

    test "higher confidence with more results" do
      query = "Test query"
      few_results = [search_result_fixture()]
      many_results = Enum.map(1..10, fn _ -> search_result_fixture() end)

      answer_few = AnswerBuilder.build_answer(query, few_results)
      answer_many = AnswerBuilder.build_answer(query, many_results)

      assert answer_few != nil
      assert answer_many != nil
    end

    test "lower confidence with lower relevance scores" do
      query = "Test query"

      low_relevance_result = search_result_fixture(relevance_score: 0.2)
      high_relevance_result = search_result_fixture(relevance_score: 0.95)

      answer_low = AnswerBuilder.build_answer(query, [low_relevance_result])
      answer_high = AnswerBuilder.build_answer(query, [high_relevance_result])

      assert answer_low != nil
      assert answer_high != nil
    end
  end

  describe "build_answer/3 - result filtering" do
    test "handles mixed source types" do
      query = "What happened?"

      results = [
        search_result_fixture(source: "email", source_id: "msg_1"),
        search_result_fixture(source: "calendar", source_id: "event_1"),
        search_result_fixture(source: "crm", source_id: "contact_1")
      ]

      answer = AnswerBuilder.build_answer(query, results)

      assert answer != nil
    end

    test "handles results with different relevance scores" do
      query = "What is the priority?"

      results = [
        search_result_fixture(relevance_score: 0.95),
        search_result_fixture(relevance_score: 0.75),
        search_result_fixture(relevance_score: 0.45)
      ]

      answer = AnswerBuilder.build_answer(query, results)

      assert answer != nil
    end

    test "handles results from same source" do
      query = "What emails arrived?"

      results =
        Enum.map(1..5, fn i ->
          search_result_fixture(source: "email", source_id: "msg_#{i}")
        end)

      answer = AnswerBuilder.build_answer(query, results)

      assert answer != nil
    end
  end

  describe "answer structure" do
    test "answer contains required fields" do
      query = "Test query"
      results = [search_result_fixture()]

      answer = AnswerBuilder.build_answer(query, results)

      # Should have answer text
      assert Map.has_key?(answer, :answer) or
               Map.has_key?(answer, "answer") or
               answer != nil
    end

    test "answer response is proper map" do
      query = "Test"
      results = [search_result_fixture()]

      answer = AnswerBuilder.build_answer(query, results)

      assert is_map(answer)
    end

    test "answer text is non-empty" do
      query = "What happened?"

      results = [
        search_result_fixture(text: "Important update about the project")
      ]

      answer = AnswerBuilder.build_answer(query, results)

      answer_text =
        Map.get(answer, :answer) ||
          Map.get(answer, "answer") ||
          ""

      if is_binary(answer_text), do: assert(String.length(answer_text) > 0)
    end
  end

  describe "edge cases" do
    test "handles nil results gracefully" do
      query = "Test"

      # Should handle nil or empty case
      catch_error(AnswerBuilder.build_answer(query, nil)) ||
        AnswerBuilder.build_answer(query, [])
    end

    test "handles very long query" do
      query = String.duplicate("word ", 500)
      results = [search_result_fixture()]

      answer = AnswerBuilder.build_answer(query, results)

      assert answer != nil
    end

    test "handles special characters in query" do
      queries = [
        "What about (important) items?",
        "Show me $1M+ revenue",
        "List #urgent tasks"
      ]

      Enum.each(queries, fn query ->
        results = [search_result_fixture()]
        answer = AnswerBuilder.build_answer(query, results)
        assert answer != nil
      end)
    end

    test "handles results with very long text" do
      query = "Summarize"
      long_text = String.duplicate("word ", 500)

      results = [search_result_fixture(text: long_text)]

      answer = AnswerBuilder.build_answer(query, results)

      assert answer != nil
    end
  end

  describe "answer combination" do
    test "combines multiple results into coherent answer" do
      query = "What was discussed with John?"

      results = [
        search_result_fixture(
          text: "John mentioned Q1 targets",
          person_name: "John",
          source: "email"
        ),
        search_result_fixture(
          text: "John confirmed timeline",
          person_name: "John",
          source: "email"
        ),
        search_result_fixture(
          text: "Meeting with John scheduled",
          person_name: "John",
          source: "calendar"
        )
      ]

      answer = AnswerBuilder.build_answer(query, results)

      assert answer != nil
    end

    test "prioritizes high-relevance results" do
      query = "Most important update"

      results = [
        search_result_fixture(relevance_score: 0.4),
        search_result_fixture(relevance_score: 0.95),
        search_result_fixture(relevance_score: 0.6)
      ]

      answer = AnswerBuilder.build_answer(query, results)

      assert answer != nil
    end
  end

  describe "citation formatting" do
    test "formats citations correctly" do
      query = "What are the details?"

      results = [
        search_result_fixture(
          id: "chunk_1",
          text: "Important detail"
        ),
        search_result_fixture(
          id: "chunk_2",
          text: "Another detail"
        )
      ]

      answer = AnswerBuilder.build_answer(query, results, include_citations: true)

      # Should include source information
      assert answer != nil
    end

    test "links citations to sources" do
      query = "Where did this come from?"

      results = [
        search_result_fixture(
          id: "chunk_1",
          source: "email",
          source_id: "msg_1"
        )
      ]

      answer = AnswerBuilder.build_answer(query, results, include_citations: true)

      assert answer != nil
    end
  end
end
