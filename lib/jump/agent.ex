defmodule Jump.Agent do
  @moduledoc """
  The Agent context handles AI agent orchestration, tool calling, and conversation management.
  """

  import Ecto.Query, warn: false
  alias Jump.Repo

  alias Jump.{Messaging, Tasks, Agents}
  alias Jump.Messaging.Message
  alias Jump.Tasks.Task
  alias Jump.Agents.Instruction

  require Logger

  @doc """
  Process a user message through the agent and return the response.
  """
  def process_message(user_id, content, thread_id \\ nil) do
    # Create user message
    {:ok, user_message} = Messaging.create_user_message(user_id, content, thread_id)

    # Get or create thread ID
    thread_id = user_message.thread_id || generate_thread_id()

    # Build agent context
    context = build_context(user_id, thread_id)

    # Run agent loop
    case Jump.Agent.Loop.run(user_id, content, context) do
      {:ok, response, tool_calls} ->
        # Create assistant message
        {:ok, assistant_message} =
          Messaging.create_assistant_message(user_id, response, thread_id)

        # Create tool messages
        tool_messages =
          Enum.map(tool_calls, fn tool_call ->
            {:ok, msg} =
              Messaging.create_tool_message(
                user_id,
                tool_call.name,
                tool_call.args,
                tool_call.result,
                thread_id,
                tool_call.task_id
              )

            msg
          end)

        {:ok, assistant_message, tool_messages}

      {:error, reason} ->
        Logger.error("Agent.process_message failed",
          user_id: user_id,
          thread_id: thread_id,
          content_preview: String.slice(content, 0, 100),
          reason: inspect(reason, pretty: true, limit: :infinity)
        )

        {:error, reason}
    end
  end

  @doc """
  Build the complete context for the agent including instructions, memory, and RAG.
  """
  def build_context(user_id, thread_id) do
    %{
      user_id: user_id,
      thread_id: thread_id,
      instructions: get_enabled_instructions(user_id),
      recent_messages: get_recent_messages(user_id, thread_id),
      active_tasks: get_active_tasks(user_id),
      current_time: DateTime.utc_now()
    }
  end

  @doc """
  Get all enabled instructions for a user.
  """
  def get_enabled_instructions(user_id) do
    Agents.get_enabled_instructions_for_user(user_id)
  end

  @doc """
  Get recent messages for context window.
  """
  def get_recent_messages(user_id, thread_id, limit \\ 20) do
    Messaging.get_thread_messages(user_id, thread_id, limit)
  end

  @doc """
  Get active tasks for the user.
  """
  def get_active_tasks(user_id) do
    Tasks.list_tasks_by_status(user_id, "running")
    |> Enum.concat(Tasks.list_tasks_by_status(user_id, "waiting"))
  end

  @doc """
  Generate a unique thread ID.
  """
  def generate_thread_id() do
    :crypto.strong_rand_bytes(16) |> Base.encode64(padding: false)
  end

  @doc """
  Resume a task from an external event.
  """
  def resume_task(task_id, event_data) do
    case Tasks.get_task!(task_id) do
      %Task{status: "waiting"} = task ->
        Jump.Agent.Loop.resume_task(task, event_data)

      _ ->
        {:error, :task_not_waiting}
    end
  end

  @doc """
  Get the system prompt with user instructions integrated.
  """
  def get_system_prompt(user_id) do
    base_prompt = get_base_system_prompt()
    instructions = get_enabled_instructions(user_id)

    if Enum.empty?(instructions) do
      base_prompt
    else
      instruction_text =
        instructions
        |> Enum.map(fn instr -> "- #{instr.title}: #{instr.content}" end)
        |> Enum.join("\n")

      """
      #{base_prompt}

      Additional Instructions:
      #{instruction_text}
      """
    end
  end

  defp get_base_system_prompt() do
    """
    You are an AI agent for financial advisors. You can read/write Gmail, manage Google Calendar, and work with HubSpot contacts and notes.

    Your capabilities include:
    - Searching and analyzing emails, calendar events, and contacts
    - Sending emails with proper threading
    - Creating calendar events and proposing meeting times
    - Listing and viewing calendar events in real-time
    - Finding and creating contacts in HubSpot
    - Adding notes to contacts
    - Managing multi-step workflows

    Guidelines:
    - Ask for clarification only when necessary
    - Keep responses concise and actionable
    - Cite sources when using information from RAG search
    - Use tools to accomplish tasks rather than just describing what you would do
    - Maintain conversation context and remember previous interactions
    - Be proactive in helping with financial advisor workflows

    Tool Usage Strategy:
    - For calendar queries: First try search_rag for historical context
    - If search_rag returns 0 results for calendar queries, IMMEDIATELY use list_calendar_events to fetch real-time data
    - Don't ask the user for configuration - use sensible defaults (today's date, primary calendar, user timezone)

    When scheduling meetings:
    - Always propose specific time slots
    - Send calendar invitations once confirmed
    - Add notes to contacts about the meeting
    - Send confirmation emails

    When handling emails:
    - Maintain proper conversation threading
    - Be professional and helpful
    - Include relevant context from previous messages
    """
  end
end
