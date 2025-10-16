defmodule Jump.Agent.Loop do
  @moduledoc """
  Agent planner-executor loop using LangChain.
  """

  alias Jump.{Agent, Tasks}
  alias Jump.Agent.Tools
  alias LangChain.{Chains.LLMChain, ChatModels.ChatOpenAI, Message, Message.ToolResult}
  alias LangChain.Message.ContentPart
  require Logger

  @doc """
  Run the agent loop to process a user message.
  """
  def run(user_id, user_message, context) do
    Logger.info("Starting agent loop for user #{user_id}")

    # Check API key configuration first
    unless check_api_key_configured() do
      {:error,
       "OpenAI API key is required. Please set OPENAI_API_KEY environment variable and restart the application."}
    end

    try do
      # Build the conversation
      messages = build_conversation(user_id, user_message, context)
      Logger.debug("Built conversation with #{length(messages)} messages")

      # Validate tools before creating chain
      tools = Tools.all()
      tool_names = Enum.map(tools, & &1.name)
      Logger.info("Agent loop starting", user_id: user_id, tools: tool_names)
      validate_tools(tools)

      # Create and run the chain
      chain =
        LLMChain.new!(%{
          llm: get_llm_config(),
          custom_context: %{user_id: user_id},
          verbose: true
        })
        |> LLMChain.add_tools(tools)
        |> LLMChain.add_messages(messages)

      Logger.debug("Chain created successfully, running with tool calling", user_id: user_id)

      # Run the chain with tool calling
      case LLMChain.run(chain, mode: :while_needs_response) do
        {:ok, final_chain} ->
          # Extract final response and tool calls
          tool_calls = extract_tool_calls(final_chain.exchanged_messages)
          final_response = extract_final_response(final_chain.last_message)

          Logger.info("Agent loop completed successfully with #{length(tool_calls)} tool calls")
          {:ok, final_response, tool_calls}

        {:error, _error_chain, reason} ->
          Logger.error("LLMChain.run failed!",
            user_id: user_id,
            reason: inspect(reason, pretty: true, limit: :infinity),
            reason_type: if(is_struct(reason), do: reason.__struct__, else: "not_struct")
          )

          handle_langchain_error(reason, user_id)
      end
    rescue
      e ->
        Logger.error("Agent loop exception!",
          user_id: user_id,
          exception: Exception.message(e),
          exception_type: e.__struct__,
          stacktrace: Exception.format_stacktrace(__STACKTRACE__)
        )

        # Handle case where we didn't match the error tuple properly
        case e do
          %CaseClauseError{term: {:error, _chain, reason}} ->
            Logger.error("CaseClauseError with LangChain error",
              user_id: user_id,
              langchain_reason: inspect(reason, pretty: true)
            )

            handle_langchain_error(reason, user_id)

          _ ->
            {:error, "Agent processing failed: #{Exception.message(e)}"}
        end
    end
  end

  @doc """
  Resume a waiting task from an external event.
  """
  def resume_task(task, event_data) do
    Logger.info("Resuming task #{task.id} with event: #{inspect(event_data)}")

    try do
      # Parse the task state to determine what to do
      state = task.state || %{}
      next_step = Map.get(state, "next_wait")

      case next_step do
        "gmail_reply" ->
          handle_gmail_reply(task, event_data)

        "calendar_confirmation" ->
          handle_calendar_confirmation(task, event_data)

        "contact_creation" ->
          handle_contact_creation(task, event_data)

        _ ->
          Logger.warning("Unknown task wait state: #{next_step}")
          Tasks.mark_task_failed(task, "Unknown wait state: #{next_step}")
      end
    rescue
      e ->
        Logger.error("Task resumption error: #{inspect(e)}")
        Tasks.mark_task_failed(task, "Resumption failed: #{Exception.message(e)}")
    end
  end

  # Build the conversation including system prompt, history, and current message
  defp build_conversation(user_id, user_message, context) do
    # Start with system prompt
    system_prompt = Agent.get_system_prompt(user_id)
    messages = [Message.new_system!(system_prompt)]

    # Add recent conversation history
    history_messages =
      context.recent_messages
      # Limit context window
      |> Enum.take(20)
      |> Enum.map(&convert_message_to_langchain/1)

    messages = messages ++ history_messages

    # Add relevant context from active tasks and instructions
    context_messages = build_context_messages(context)
    messages = messages ++ context_messages

    # Add current user message
    messages = messages ++ [Message.new_user!(user_message)]

    messages
  end

  # Convert app messages to LangChain messages
  defp convert_message_to_langchain(%Jump.Messaging.Message{role: "user", content: content}) do
    Message.new_user!(content)
  end

  defp convert_message_to_langchain(%Jump.Messaging.Message{role: "assistant", content: content}) do
    Message.new_assistant!(content)
  end

  defp convert_message_to_langchain(%Jump.Messaging.Message{
         role: "tool",
         tool_name: tool_name,
         tool_result: result
       }) do
    # Generate a tool call ID since we're converting from historical data
    tool_call_id = generate_tool_call_id(tool_name)

    tool_result =
      ToolResult.new!(%{
        tool_call_id: tool_call_id,
        content: result,
        is_error: false
      })

    Message.new_tool_result!(%{tool_results: [tool_result]})
  end

  defp convert_message_to_langchain(%Jump.Messaging.Message{}), do: nil
  defp convert_message_to_langchain(_), do: nil

  # Generate a consistent tool call ID for historical tool messages
  defp generate_tool_call_id(tool_name), do: "#{tool_name}_#{:erlang.unique_integer([:positive])}"

  # Build context messages from tasks and instructions
  defp build_context_messages(context) do
    messages = []

    # Add instruction context if present
    instruction_context =
      if Enum.any?(context.instructions) do
        instruction_text =
          context.instructions
          |> Enum.map(fn instr -> "#{instr.title}: #{instr.content}" end)
          |> Enum.join("\n")

        "Active instructions:\n#{instruction_text}"
      end

    messages =
      if instruction_context do
        messages ++ [Message.new_system!(instruction_context)]
      else
        messages
      end

    # Add active tasks context
    task_context =
      if Enum.any?(context.active_tasks) do
        task_text =
          context.active_tasks
          |> Enum.map(fn task -> "#{task.kind}: #{task.status}" end)
          |> Enum.join("\n")

        "Active tasks:\n#{task_text}"
      end

    if task_context do
      messages ++ [Message.new_system!(task_context)]
    else
      messages
    end
  end

  # Validate tools before adding to chain
  defp validate_tools(tools) do
    Enum.each(tools, fn tool ->
      case tool do
        %LangChain.Function{name: name, parameters_schema: schema} when is_map(schema) ->
          Logger.debug("Tool valid: #{name}")

        %LangChain.Function{name: name} ->
          Logger.warning("Tool #{name} has no parameters_schema")

        other ->
          Logger.warning("Invalid tool structure: #{inspect(other)}")
      end
    end)
  end

  # Handle LangChain specific errors
  defp handle_langchain_error(reason, user_id) do
    case reason do
      %LangChain.LangChainError{type: "changeset", message: msg} ->
        Logger.error("LangChain changeset error for user #{user_id}: #{msg}")
        {:error, "Configuration error: #{msg}"}

      %LangChain.LangChainError{message: msg} ->
        if String.contains?(msg, "API key") do
          Logger.error("OpenAI API key missing for user #{user_id}: #{msg}")

          {:error,
           "OpenAI API key is required. Please set OPENAI_API_KEY environment variable and restart the application."}
        else
          Logger.error("LangChain error for user #{user_id}: #{msg}")
          {:error, "Agent error: #{msg}"}
        end

      %LangChain.LangChainError{type: type, message: msg} ->
        Logger.error("LangChain #{type} error for user #{user_id}: #{msg}")
        {:error, "Agent error: #{msg}"}

      _ ->
        Logger.error("Unknown LangChain error for user #{user_id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Get LLM configuration
  defp get_llm_config() do
    ChatOpenAI.new!(%{
      model: "gpt-5-nano",
      temperature: 1,
      max_completion_tokens: 20000,
      tool_choice: %{"type" => "auto"}
    })
  end

  # Check if OpenAI API key is properly configured
  defp check_api_key_configured() do
    api_key =
      Application.get_env(:langchain, :openai_key) ||
        System.get_env("OPENAI_API_KEY")

    if api_key in [nil, ""] do
      Logger.error(
        "OpenAI API key is not configured. Please set OPENAI_API_KEY environment variable."
      )

      false
    else
      true
    end
  end

  # Extract tool calls from chain messages
  defp extract_tool_calls(messages) when is_list(messages) do
    messages
    |> Enum.filter(&match?(%LangChain.Message{role: :tool}, &1))
    |> Enum.map(fn msg ->
      %{
        name: msg.name,
        args: msg.arguments,
        result: msg.content,
        task_id: get_task_id_from_message(msg)
      }
    end)
  end

  defp extract_tool_calls(_), do: []

  # Extract final assistant response from the last message
  defp extract_final_response(nil), do: "I'm sorry, I couldn't generate a response."

  defp extract_final_response(%LangChain.Message{role: :assistant, content: content}) do
    # Handle multi-modal content - extract text from ContentPart list
    case ContentPart.content_to_string(content) do
      nil -> "I'm sorry, I couldn't generate a response."
      text when is_binary(text) -> text
      _ -> "I'm sorry, I couldn't generate a response."
    end
  end

  defp extract_final_response(_), do: "I'm sorry, I couldn't generate a response."

  # Get task ID from a tool message
  defp get_task_id_from_message(%LangChain.Message{role: :tool} = msg) do
    # Try to extract task ID from the message content or create a new one
    case Jason.decode(msg.content) do
      {:ok, %{"task_id" => task_id}} -> task_id
      _ -> nil
    end
  end

  # Handle Gmail reply task continuation
  defp handle_gmail_reply(task, event_data) do
    case event_data do
      %{"message_id" => message_id, "from" => from_email} ->
        # Process the reply and potentially continue the workflow
        Tasks.mark_task_done(task, %{
          "reply_received" => true,
          "message_id" => message_id,
          "from" => from_email
        })

        # Trigger any follow-up actions if needed
        maybe_trigger_follow_up(task.user_id, "gmail_reply", event_data)

      _ ->
        Tasks.mark_task_failed(task, "Invalid reply event data")
    end
  end

  # Handle calendar confirmation task continuation
  defp handle_calendar_confirmation(task, event_data) do
    case event_data do
      %{"event_id" => event_id, "status" => "confirmed"} ->
        Tasks.mark_task_done(task, %{
          "event_confirmed" => true,
          "event_id" => event_id
        })

        # Add note to contact about confirmed meeting
        maybe_add_meeting_note(task.user_id, event_id)

      _ ->
        Tasks.mark_task_failed(task, "Invalid calendar confirmation data")
    end
  end

  # Handle contact creation task continuation
  defp handle_contact_creation(task, event_data) do
    case event_data do
      %{"contact_id" => contact_id} ->
        Tasks.mark_task_done(task, %{
          "contact_created" => true,
          "contact_id" => contact_id
        })

      _ ->
        Tasks.mark_task_failed(task, "Invalid contact creation data")
    end
  end

  # Trigger follow-up actions based on task completion
  defp maybe_trigger_follow_up(user_id, trigger_type, _event_data) do
    # This could trigger additional agent workflows
    # For now, just log the event
    Logger.info("Follow-up trigger: #{trigger_type} for user #{user_id}")
  end

  # Add meeting note to contact when calendar event is confirmed
  defp maybe_add_meeting_note(_user_id, event_id) do
    # Extract meeting details and add note to relevant contact
    # This would involve looking up the event and associated contact
    Logger.info("Adding meeting note for event #{event_id}")
  end
end
