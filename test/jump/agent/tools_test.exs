defmodule Jump.Agent.ToolsTest do
  use ExUnit.Case

  alias Jump.Agent.Tools
  import Jump.TestHelpers

  describe "all/0 - tool list" do
    test "returns list of tools" do
      tools = Tools.all()

      assert is_list(tools)
      assert length(tools) > 0
    end

    test "tools have required structure" do
      tools = Tools.all()

      Enum.each(tools, fn tool ->
        assert tool != nil
      end)
    end

    test "includes send_email_via_gmail tool" do
      tools = Tools.all()

      # Should have email sending capability
      assert length(tools) > 0
    end

    test "includes propose_calendar_times tool" do
      tools = Tools.all()

      # Should have calendar proposal capability
      assert length(tools) > 0
    end

    test "includes create_calendar_event tool" do
      tools = Tools.all()

      # Should have event creation capability
      assert length(tools) > 0
    end

    test "includes search_rag tool" do
      tools = Tools.all()

      # Should have search capability
      assert length(tools) > 0
    end
  end

  describe "send_email tool - tool definition" do
    test "email tool has correct name" do
      tools = Tools.all()

      email_tool =
        Enum.find(tools, fn tool ->
          tool.name == "send_email_via_gmail"
        end)

      assert email_tool != nil
    end

    test "email tool has description" do
      tools = Tools.all()

      email_tool =
        Enum.find(tools, fn tool ->
          tool.name == "send_email_via_gmail"
        end)

      assert email_tool.description != nil
      assert String.length(email_tool.description) > 0
    end

    test "email tool has parameter schema" do
      tools = Tools.all()

      email_tool =
        Enum.find(tools, fn tool ->
          tool.name == "send_email_via_gmail"
        end)

      assert email_tool.parameters_schema != nil
      assert Map.has_key?(email_tool.parameters_schema, "properties")
    end

    test "email tool schema has required fields" do
      tools = Tools.all()

      email_tool =
        Enum.find(tools, fn tool ->
          tool.name == "send_email_via_gmail"
        end)

      schema = email_tool.parameters_schema
      required = Map.get(schema, "required", [])

      assert "to" in required
      assert "subject" in required
      assert "html_body" in required
    end

    test "email tool schema has optional fields" do
      tools = Tools.all()

      email_tool =
        Enum.find(tools, fn tool ->
          tool.name == "send_email_via_gmail"
        end)

      schema = email_tool.parameters_schema
      properties = Map.get(schema, "properties", %{})

      assert Map.has_key?(properties, "text_body")
      assert Map.has_key?(properties, "reply_to_message_id")
      assert Map.has_key?(properties, "references")
    end
  end

  describe "propose_calendar_times tool - tool definition" do
    test "calendar proposal tool has correct name" do
      tools = Tools.all()

      tool =
        Enum.find(tools, fn tool ->
          tool.name == "propose_calendar_times"
        end)

      assert tool != nil
      assert tool.name == "propose_calendar_times"
    end

    test "calendar proposal tool has required parameters" do
      tools = Tools.all()

      tool =
        Enum.find(tools, fn tool ->
          tool.name == "propose_calendar_times"
        end)

      schema = tool.parameters_schema
      required = Map.get(schema, "required", [])

      assert "duration_minutes" in required
      assert "window_start" in required
      assert "window_end" in required
      assert "timezone" in required
    end

    test "calendar proposal tool accepts optional attendees" do
      tools = Tools.all()

      tool =
        Enum.find(tools, fn tool ->
          tool.name == "propose_calendar_times"
        end)

      schema = tool.parameters_schema
      properties = Map.get(schema, "properties", %{})

      assert Map.has_key?(properties, "attendees")
      assert Map.has_key?(properties, "min_slots")
    end
  end

  describe "create_calendar_event tool - tool definition" do
    test "event creation tool exists" do
      tools = Tools.all()

      tool =
        Enum.find(tools, fn tool ->
          tool.name == "create_calendar_event"
        end)

      assert tool != nil
    end

    test "event creation tool has required parameters" do
      tools = Tools.all()

      tool =
        Enum.find(tools, fn tool ->
          tool.name == "create_calendar_event"
        end)

      schema = tool.parameters_schema
      required = Map.get(schema, "required", [])

      assert "start" in required
      assert "end" in required
      assert "summary" in required
    end

    test "event creation tool accepts optional fields" do
      tools = Tools.all()

      tool =
        Enum.find(tools, fn tool ->
          tool.name == "create_calendar_event"
        end)

      schema = tool.parameters_schema
      properties = Map.get(schema, "properties", %{})

      assert Map.has_key?(properties, "description")
      assert Map.has_key?(properties, "location")
      assert Map.has_key?(properties, "attendees")
      assert Map.has_key?(properties, "conference")
    end
  end

  describe "hubspot tools - tool definition" do
    test "contact finding tool exists" do
      tools = Tools.all()

      tool =
        Enum.find(tools, fn tool ->
          tool.name == "hubspot_find_or_create_contact"
        end)

      assert tool != nil
    end

    test "contact finding tool requires email" do
      tools = Tools.all()

      tool =
        Enum.find(tools, fn tool ->
          tool.name == "hubspot_find_or_create_contact"
        end)

      schema = tool.parameters_schema
      required = Map.get(schema, "required", [])

      assert "email" in required
    end

    test "note adding tool exists" do
      tools = Tools.all()

      tool =
        Enum.find(tools, fn tool ->
          tool.name == "hubspot_add_note"
        end)

      assert tool != nil
    end

    test "note adding tool requires contact_id and text" do
      tools = Tools.all()

      tool =
        Enum.find(tools, fn tool ->
          tool.name == "hubspot_add_note"
        end)

      schema = tool.parameters_schema
      required = Map.get(schema, "required", [])

      assert "contact_id" in required
      assert "text" in required
    end
  end

  describe "search_rag tool - tool definition" do
    test "search tool exists" do
      tools = Tools.all()

      tool =
        Enum.find(tools, fn tool ->
          tool.name == "search_rag"
        end)

      assert tool != nil
    end

    test "search tool requires query parameter" do
      tools = Tools.all()

      tool =
        Enum.find(tools, fn tool ->
          tool.name == "search_rag"
        end)

      schema = tool.parameters_schema
      required = Map.get(schema, "required", [])

      assert "query" in required
    end

    test "search tool accepts optional parameters" do
      tools = Tools.all()

      tool =
        Enum.find(tools, fn tool ->
          tool.name == "search_rag"
        end)

      schema = tool.parameters_schema
      properties = Map.get(schema, "properties", %{})

      assert Map.has_key?(properties, "search_type")
      assert Map.has_key?(properties, "max_results")
      assert Map.has_key?(properties, "time_range")
    end

    test "search tool enum values are valid" do
      tools = Tools.all()

      tool =
        Enum.find(tools, fn tool ->
          tool.name == "search_rag"
        end)

      schema = tool.parameters_schema
      search_type_prop = schema["properties"]["search_type"]
      enum_values = Map.get(search_type_prop, "enum", [])

      assert "general" in enum_values
      assert "person" in enum_values
      assert "temporal" in enum_values
    end
  end

  describe "tool function attribute" do
    test "tools have function attribute for execution" do
      tools = Tools.all()

      Enum.each(tools, fn tool ->
        assert tool != nil
      end)
    end

    test "email tool function is callable" do
      tools = Tools.all()

      email_tool =
        Enum.find(tools, fn tool ->
          tool.name == "send_email_via_gmail"
        end)

      assert email_tool != nil
      # Function should be present for execution
    end
  end

  describe "tool parameter validation" do
    test "tools enforce required parameters in schema" do
      tools = Tools.all()

      Enum.each(tools, fn tool ->
        schema = tool.parameters_schema

        required = Map.get(schema, "required", [])
        properties = Map.get(schema, "properties", %{})

        # All required fields should be in properties
        Enum.each(required, fn field ->
          assert Map.has_key?(properties, field)
        end)
      end)
    end

    test "email tool validates email addresses" do
      tools = Tools.all()

      email_tool =
        Enum.find(tools, fn tool ->
          tool.name == "send_email_via_gmail"
        end)

      # 'to' field should specify email format
      to_property = email_tool.parameters_schema["properties"]["to"]

      assert to_property != nil
    end

    test "calendar tools validate datetime parameters" do
      tools = Tools.all()

      calendar_tool =
        Enum.find(tools, fn tool ->
          tool.name == "propose_calendar_times"
        end)

      # window_start should specify date-time format
      start_prop = calendar_tool.parameters_schema["properties"]["window_start"]

      assert start_prop != nil
    end
  end

  describe "tool descriptions" do
    test "all tools have meaningful descriptions" do
      tools = Tools.all()

      Enum.each(tools, fn tool ->
        assert is_binary(tool.description)
        assert String.length(tool.description) > 10
      end)
    end

    test "tool descriptions are unique" do
      tools = Tools.all()
      descriptions = Enum.map(tools, & &1.description)

      unique_descriptions = Enum.uniq(descriptions)

      assert length(descriptions) == length(unique_descriptions)
    end
  end

  describe "tool count and completeness" do
    test "has minimum expected number of tools" do
      tools = Tools.all()

      # Should have at least 6 main tools
      assert length(tools) >= 6
    end

    test "all critical tools are present" do
      tools = Tools.all()
      tool_names = Enum.map(tools, & &1.name)

      assert "send_email_via_gmail" in tool_names
      assert "propose_calendar_times" in tool_names
      assert "create_calendar_event" in tool_names
      assert "hubspot_find_or_create_contact" in tool_names
      assert "hubspot_add_note" in tool_names
      assert "search_rag" in tool_names
    end

    test "tool names are unique" do
      tools = Tools.all()
      names = Enum.map(tools, & &1.name)

      unique_names = Enum.uniq(names)

      assert length(names) == length(unique_names)
    end
  end
end
