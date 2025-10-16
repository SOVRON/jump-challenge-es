defmodule Jump.Agent.Context do
  @moduledoc """
  Context building and management for the AI agent.
  """

  alias Jump.{Agent, Messaging, Tasks, RAG}
  alias Jump.Agents.Instruction
  require Logger

  @doc """
  Build comprehensive context for the agent including:
  - System prompt with user instructions
  - Recent conversation history
  - Relevant RAG search results
  - Active task information
  """
  def build_full_context(user_id, user_message, thread_id \\ nil) do
    # Base context
    base_context = Agent.build_context(user_id, thread_id)

    # Search RAG for relevant context based on user message
    rag_context = search_rag_context(user_id, user_message)

    # Merge all context
    Map.merge(base_context, %{
      rag_context: rag_context,
      user_message: user_message
    })
  end

  @doc """
  Build context for a specific task or workflow.
  """
  def build_task_context(user_id, task_kind, task_data) do
    %{
      user_id: user_id,
      task_kind: task_kind,
      task_data: task_data,
      instructions: get_relevant_instructions(user_id, task_kind),
      current_time: DateTime.utc_now()
    }
  end

  @doc """
  Search RAG for context relevant to the user's message.
  """
  def search_rag_context(user_id, message, max_results \\ 5) do
    try do
      # Determine search type based on message content
      search_type = infer_search_type(message)

      # Perform search
      results =
        RAG.Retriever.search_and_retrieve(
          user_id,
          message,
          search_type,
          max_results,
          "recent"
        )

      # Build context from results
      %{
        search_type: search_type,
        results_count: length(results),
        results: results,
        summary: summarize_search_results(results)
      }
    rescue
      e ->
        Logger.error("RAG context search failed: #{inspect(e)}")

        %{
          search_type: "general",
          results_count: 0,
          results: [],
          summary: nil,
          error: Exception.message(e)
        }
    end
  end

  @doc """
  Infer the best search type based on message content.
  """
  def infer_search_type(message) do
    message_lower = String.downcase(message)

    cond do
      contains_any?(message_lower, ["schedule", "meeting", "appointment", "calendar"]) ->
        "scheduling"

      contains_any?(message_lower, ["contact", "person", "who", "email"]) ->
        "person"

      contains_any?(message_lower, ["when", "date", "time", "yesterday", "today", "tomorrow"]) ->
        "temporal"

      contains_any?(message_lower, ["note", "information", "details"]) ->
        "contact"

      true ->
        "general"
    end
  end

  @doc """
  Get instructions relevant to a specific task kind.
  """
  def get_relevant_instructions(user_id, task_kind) do
    all_instructions = Agent.get_enabled_instructions(user_id)

    # Filter instructions that might be relevant to the task
    Enum.filter(all_instructions, fn instruction ->
      title_lower = String.downcase(instruction.title)
      content_lower = String.downcase(instruction.content)

      # Check if instruction mentions keywords related to the task
      task_keywords = get_task_keywords(task_kind)

      Enum.any?(task_keywords, fn keyword ->
        String.contains?(title_lower, keyword) or String.contains?(content_lower, keyword)
      end)
    end)
  end

  @doc """
  Build context for resuming a task from an external event.
  """
  def build_resume_context(task, event_data) do
    %{
      user_id: task.user_id,
      task_id: task.id,
      task_kind: task.kind,
      event_data: event_data,
      task_state: task.state,
      correlation_key: task.correlation_key,
      current_time: DateTime.utc_now()
    }
  end

  @doc """
  Create a summary of search results for context.
  """
  def summarize_search_results([]), do: nil

  def summarize_search_results(results) do
    # Group results by source type
    grouped = Enum.group_by(results, & &1.source)

    summary_parts =
      Enum.map(grouped, fn {source, items} ->
        count = length(items)
        source_name = format_source_name(source)
        "#{count} #{source_name}"
      end)

    Enum.join(summary_parts, ", ")
  end

  @doc """
  Get recent conversation history with context window management.
  """
  def get_conversation_history(user_id, thread_id, limit \\ 10) do
    messages = Messaging.get_thread_messages(user_id, thread_id, limit)

    # Process messages to include relevant metadata
    Enum.map(messages, fn message ->
      base = %{
        id: message.id,
        role: message.role,
        content: message.content,
        timestamp: message.inserted_at
      }

      # Add tool-specific metadata
      case message.role do
        "tool" ->
          Map.merge(base, %{
            tool_name: message.tool_name,
            tool_args: message.tool_args,
            tool_result: message.tool_result
          })

        _ ->
          base
      end
    end)
  end

  @doc """
  Check if additional context is needed for a task.
  """
  def needs_additional_context?(task_kind, current_context) do
    case task_kind do
      "schedule_meeting" ->
        # Need calendar availability and contact information
        not has_calendar_info?(current_context) or not has_contact_info?(current_context)

      "send_email" ->
        # Need recipient information and context
        not has_recipient_info?(current_context)

      "create_contact" ->
        # Need minimal contact information
        not has_contact_info?(current_context)

      _ ->
        false
    end
  end

  @doc """
  Enrich context with additional information when needed.
  """
  def enrich_context(context, task_kind) do
    enriched = context

    enriched =
      if needs_additional_context?(task_kind, enriched) do
        case task_kind do
          "schedule_meeting" ->
            add_calendar_context(enriched)

          "send_email" ->
            add_contact_context(enriched)

          _ ->
            enriched
        end
      else
        enriched
      end

    enriched
  end

  # Private helpers

  defp contains_any?(string, patterns) do
    Enum.any?(patterns, fn pattern -> String.contains?(string, pattern) end)
  end

  defp get_task_keywords("schedule_meeting"),
    do: ["meeting", "schedule", "calendar", "appointment"]

  defp get_task_keywords("send_email"), do: ["email", "send", "reply", "message"]
  defp get_task_keywords("create_contact"), do: ["contact", "person", "client", "customer"]
  defp get_task_keywords("search"), do: ["search", "find", "look", "information"]
  defp get_task_keywords(_), do: []

  defp format_source_name("gmail"), do: "emails"
  defp format_source_name("hubspot"), do: "HubSpot records"
  defp format_source_name("calendar"), do: "calendar events"
  defp format_source_name(source), do: "#{source} items"

  defp has_calendar_info?(context) do
    Map.has_key?(context, :calendar_free_busy) or
      (Map.has_key?(context, :rag_context) and
         Enum.any?(context.rag_context.results, &(&1.source == "calendar")))
  end

  defp has_contact_info?(context) do
    Map.has_key?(context, :contact_info) or
      (Map.has_key?(context, :rag_context) and
         Enum.any?(context.rag_context.results, &(&1.source == "hubspot")))
  end

  defp has_recipient_info?(context) do
    Map.has_key?(context, :recipient_info) or
      (Map.has_key?(context, :rag_context) and
         Enum.any?(context.rag_context.results, fn result ->
           Map.has_key?(result.meta, "person_email") or
             Map.has_key?(result.meta, "participants")
         end))
  end

  defp add_calendar_context(context) do
    # This would typically fetch calendar availability
    # For now, just mark that calendar info was requested
    Map.put(context, :calendar_requested, true)
  end

  defp add_contact_context(context) do
    # This would typically fetch relevant contact information
    # For now, just mark that contact info was requested
    Map.put(context, :contact_requested, true)
  end
end
