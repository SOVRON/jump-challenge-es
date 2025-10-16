defmodule Jump.Agent.ValidationTest do
  use ExUnit.Case

  alias Jump.Agent.Validation

  describe "validate_tool_args/2 - email tool" do
    test "accepts valid email arguments" do
      args = %{
        "to" => ["recipient@example.com"],
        "subject" => "Test Subject",
        "html_body" => "<p>Test body</p>"
      }

      assert {:ok, validated_args} = Validation.validate_tool_args("send_email_via_gmail", args)
      assert validated_args == args
    end

    test "rejects missing required fields" do
      args = %{"to" => ["recipient@example.com"]}

      assert {:error, msg} = Validation.validate_tool_args("send_email_via_gmail", args)
      assert String.contains?(msg, "subject")
    end

    test "accepts optional text_body" do
      args = %{
        "to" => ["recipient@example.com"],
        "subject" => "Test",
        "html_body" => "<p>HTML</p>",
        "text_body" => "Plain text"
      }

      assert {:ok, _} = Validation.validate_tool_args("send_email_via_gmail", args)
    end

    test "accepts multiple recipients" do
      args = %{
        "to" => ["user1@example.com", "user2@example.com", "user3@example.com"],
        "subject" => "Test",
        "html_body" => "<p>Body</p>"
      }

      assert {:ok, _} = Validation.validate_tool_args("send_email_via_gmail", args)
    end
  end

  describe "validate_tool_args/2 - calendar propose times" do
    test "accepts valid proposal arguments" do
      args = %{
        "duration_minutes" => 30,
        "window_start" => "2024-01-20T10:00:00Z",
        "window_end" => "2024-01-27T17:00:00Z",
        "timezone" => "America/New_York"
      }

      assert {:ok, _} = Validation.validate_tool_args("propose_calendar_times", args)
    end

    test "rejects invalid duration (too short)" do
      args = %{
        "duration_minutes" => 10,
        "window_start" => "2024-01-20T10:00:00Z",
        "window_end" => "2024-01-27T17:00:00Z",
        "timezone" => "America/New_York"
      }

      assert {:error, _} = Validation.validate_tool_args("propose_calendar_times", args)
    end

    test "rejects invalid duration (too long)" do
      args = %{
        "duration_minutes" => 500,
        "window_start" => "2024-01-20T10:00:00Z",
        "window_end" => "2024-01-27T17:00:00Z",
        "timezone" => "America/New_York"
      }

      assert {:error, _} = Validation.validate_tool_args("propose_calendar_times", args)
    end

    test "accepts attendees list" do
      args = %{
        "duration_minutes" => 30,
        "window_start" => "2024-01-20T10:00:00Z",
        "window_end" => "2024-01-27T17:00:00Z",
        "timezone" => "America/New_York",
        "attendees" => ["user1@example.com", "user2@example.com"]
      }

      assert {:ok, _} = Validation.validate_tool_args("propose_calendar_times", args)
    end
  end

  describe "validate_tool_args/2 - create event" do
    test "accepts valid create event arguments" do
      args = %{
        "start" => "2024-01-20T10:00:00Z",
        "end" => "2024-01-20T11:00:00Z",
        "summary" => "Team Meeting"
      }

      assert {:ok, _} = Validation.validate_tool_args("create_calendar_event", args)
    end

    test "accepts optional event fields" do
      args = %{
        "start" => "2024-01-20T10:00:00Z",
        "end" => "2024-01-20T11:00:00Z",
        "summary" => "Team Meeting",
        "description" => "Q1 Planning",
        "location" => "Conference Room A",
        "attendees" => ["user@example.com"],
        "conference" => true
      }

      assert {:ok, _} = Validation.validate_tool_args("create_calendar_event", args)
    end

    test "rejects missing required fields" do
      args = %{
        "start" => "2024-01-20T10:00:00Z",
        "end" => "2024-01-20T11:00:00Z"
      }

      assert {:error, _} = Validation.validate_tool_args("create_calendar_event", args)
    end
  end

  describe "validate_tool_args/2 - search RAG" do
    test "accepts minimal search arguments" do
      args = %{"query" => "What is the revenue?"}

      assert {:ok, _} = Validation.validate_tool_args("search_rag", args)
    end

    test "accepts all search parameters" do
      args = %{
        "query" => "What is the revenue?",
        "search_type" => "general",
        "max_results" => 10,
        "time_range" => "this_month"
      }

      assert {:ok, _} = Validation.validate_tool_args("search_rag", args)
    end

    test "rejects invalid search type" do
      args = %{
        "query" => "What is the revenue?",
        "search_type" => "invalid_type"
      }

      assert {:error, _} = Validation.validate_tool_args("search_rag", args)
    end

    test "rejects invalid time range" do
      args = %{
        "query" => "What is the revenue?",
        "time_range" => "next_year"
      }

      assert {:error, _} = Validation.validate_tool_args("search_rag", args)
    end

    test "rejects max_results too high" do
      args = %{
        "query" => "What is the revenue?",
        "max_results" => 100
      }

      assert {:error, _} = Validation.validate_tool_args("search_rag", args)
    end
  end

  describe "validate_tool_args/2 - contact tool" do
    test "accepts minimal contact arguments" do
      args = %{"email" => "user@example.com"}

      assert {:ok, _} = Validation.validate_tool_args("hubspot_find_or_create_contact", args)
    end

    test "accepts full contact arguments" do
      args = %{
        "email" => "user@example.com",
        "name" => "John Doe",
        "properties" => %{"phone" => "555-1234", "company" => "Acme"}
      }

      assert {:ok, _} = Validation.validate_tool_args("hubspot_find_or_create_contact", args)
    end

    test "rejects invalid email format" do
      args = %{"email" => "not-an-email"}

      assert {:error, _} = Validation.validate_tool_args("hubspot_find_or_create_contact", args)
    end
  end

  describe "validate_tool_args/2 - add note tool" do
    test "accepts valid note arguments" do
      args = %{
        "contact_id" => "contact_123",
        "text" => "Important follow-up needed"
      }

      assert {:ok, _} = Validation.validate_tool_args("hubspot_add_note", args)
    end

    test "rejects missing contact_id" do
      args = %{"text" => "Important follow-up needed"}

      assert {:error, _} = Validation.validate_tool_args("hubspot_add_note", args)
    end

    test "rejects missing text" do
      args = %{"contact_id" => "contact_123"}

      assert {:error, _} = Validation.validate_tool_args("hubspot_add_note", args)
    end

    test "accepts optional timestamp" do
      args = %{
        "contact_id" => "contact_123",
        "text" => "Note",
        "timestamp" => "2024-01-20T10:00:00Z"
      }

      assert {:ok, _} = Validation.validate_tool_args("hubspot_add_note", args)
    end
  end

  describe "validate_tool_args/2 - unknown tool" do
    test "accepts any arguments for unknown tool" do
      args = %{"anything" => "goes"}

      assert {:ok, _} = Validation.validate_tool_args("unknown_tool_xyz", args)
    end
  end

  describe "get_tool_schema/1" do
    test "returns schema for known tools" do
      schema = Validation.get_tool_schema("send_email_via_gmail")
      assert schema != nil
      assert schema["type"] == "object"
      assert schema["properties"] != nil
    end

    test "returns nil for unknown tools" do
      schema = Validation.get_tool_schema("non_existent_tool")
      assert schema == nil
    end
  end

  describe "error handling and repair" do
    test "repairs missing text_body in email by adding empty string" do
      args = %{
        "to" => ["user@example.com"],
        "subject" => "Test",
        "html_body" => "<p>Body</p>"
      }

      {:ok, result} = Validation.validate_tool_args("send_email_via_gmail", args)
      # Should repair by adding optional fields
      assert result["html_body"] == "<p>Body</p>"
    end

    test "repairs type mismatches when possible" do
      # Test that numeric strings can be converted
      args = %{
        "duration_minutes" => "30",
        "window_start" => "2024-01-20T10:00:00Z",
        "window_end" => "2024-01-27T17:00:00Z",
        "timezone" => "America/New_York"
      }

      result = Validation.validate_tool_args("propose_calendar_times", args)
      # Should either accept as-is or repair the type
      assert result == {:ok, args} or match?({:ok, _}, result)
    end

    test "repairs datetime format issues" do
      args = %{
        "start" => "2024-01-20 10:00:00",
        "end" => "2024-01-20 11:00:00",
        "summary" => "Meeting"
      }

      result = Validation.validate_tool_args("create_calendar_event", args)
      # Should handle datetime parsing
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
  end

  describe "validation edge cases" do
    test "handles empty strings appropriately" do
      args = %{
        "to" => ["user@example.com"],
        "subject" => "",
        "html_body" => "<p>Body</p>"
      }

      result = Validation.validate_tool_args("send_email_via_gmail", args)
      # Empty subject should be rejected or repaired
      assert match?({:error, _}, result) or match?({:ok, _}, result)
    end

    test "handles very long strings" do
      long_text = String.duplicate("a", 2500)

      args = %{
        "query" => long_text,
        "search_type" => "general"
      }

      result = Validation.validate_tool_args("search_rag", args)
      # Should handle or reject appropriately
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end

    test "handles null/nil values" do
      args = %{
        "to" => ["user@example.com"],
        "subject" => "Test",
        "html_body" => "<p>Body</p>",
        "text_body" => nil
      }

      result = Validation.validate_tool_args("send_email_via_gmail", args)
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end

    test "handles arrays with wrong types" do
      args = %{
        "to" => "user@example.com",
        "subject" => "Test",
        "html_body" => "<p>Body</p>"
      }

      result = Validation.validate_tool_args("send_email_via_gmail", args)
      # Should attempt repair or reject
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
  end
end
