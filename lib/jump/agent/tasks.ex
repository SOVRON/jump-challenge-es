defmodule Jump.Agent.Tasks do
  @moduledoc """
  Task management for agent workflows including continuation and event handling.
  """

  alias Jump.{Tasks, Agent, Messaging}
  alias Jump.Tasks.Task
  require Logger

  @doc """
  Create a new agent task with proper state management.
  """
  def create_agent_task(user_id, kind, input, state \\ %{}, correlation_key \\ nil) do
    correlation_key = correlation_key || generate_correlation_key(user_id, kind, input)

    Tasks.create_task(%{
      user_id: user_id,
      kind: kind,
      status: "queued",
      input: input,
      state: state,
      correlation_key: correlation_key
    })
  end

  @doc """
  Find or create a task with idempotency.
  """
  def find_or_create_task(user_id, kind, correlation_key, input, state \\ %{}) do
    Tasks.find_or_create_task(user_id, kind, correlation_key, %{
      input: input,
      state: state,
      status: "queued"
    })
  end

  @doc """
  Mark a task as waiting for external event.
  """
  def mark_task_waiting(task, next_wait, additional_state \\ %{}) do
    updated_state = Map.merge(task.state || %{}, additional_state)
    updated_state = Map.put(updated_state, "next_wait", next_wait)

    updated_state =
      Map.put(updated_state, "wait_started_at", DateTime.to_iso8601(DateTime.utc_now()))

    Tasks.update_task(task, %{
      status: "waiting",
      state: updated_state
    })
  end

  @doc """
  Resume a task from an external event.
  """
  def resume_task_from_event(user_id, event_data) do
    correlation_key = get_correlation_key_from_event(event_data)

    case Tasks.get_task_by_correlation_key(user_id, correlation_key) do
      nil ->
        Logger.warning("No task found for correlation key: #{correlation_key}")
        {:error, :task_not_found}

      %Task{status: "waiting"} = task ->
        Logger.info("Resuming task #{task.id} from event")
        handle_task_resumption(task, event_data)

      task ->
        Logger.warning("Task #{task.id} found but not in waiting state: #{task.status}")
        {:error, :task_not_waiting}
    end
  end

  @doc """
  Handle task timeout for waiting tasks.
  """
  def handle_task_timeout(task) do
    wait_timeout = get_wait_timeout(task.kind)
    wait_started_at = get_in(task.state, ["wait_started_at"])

    if wait_started_at do
      case DateTime.from_iso8601(wait_started_at) do
        {:ok, wait_dt, _} ->
          if DateTime.diff(DateTime.utc_now(), wait_dt) > wait_timeout do
            Logger.warning("Task #{task.id} timed out waiting for event")
            Tasks.mark_task_failed(task, "Task timed out waiting for external event")
            true
          else
            false
          end

        _ ->
          false
      end
    else
      false
    end
  end

  @doc """
  Process Gmail webhook event for task continuation.
  """
  def process_gmail_event(user_id, event_data) do
    Logger.info("Processing Gmail event for user #{user_id}: #{inspect(event_data)}")

    # Extract correlation information from Gmail event
    correlation_key = extract_gmail_correlation_key(event_data)

    if correlation_key do
      resume_task_from_event(user_id, Map.put(event_data, "correlation_key", correlation_key))
    else
      # Try to find tasks by thread ID or message ID
      handle_gmail_fallback(user_id, event_data)
    end
  end

  @doc """
  Process Calendar webhook event for task continuation.
  """
  def process_calendar_event(user_id, event_data) do
    Logger.info("Processing Calendar event for user #{user_id}: #{inspect(event_data)}")

    correlation_key = extract_calendar_correlation_key(event_data)

    if correlation_key do
      resume_task_from_event(user_id, Map.put(event_data, "correlation_key", correlation_key))
    else
      handle_calendar_fallback(user_id, event_data)
    end
  end

  @doc """
  Process HubSpot webhook event for task continuation.
  """
  def process_hubspot_event(user_id, event_data) do
    Logger.info("Processing HubSpot event for user #{user_id}: #{inspect(event_data)}")

    correlation_key = extract_hubspot_correlation_key(event_data)

    if correlation_key do
      resume_task_from_event(user_id, Map.put(event_data, "correlation_key", correlation_key))
    else
      handle_hubspot_fallback(user_id, event_data)
    end
  end

  @doc """
  Create a continuation task for multi-step workflows.
  """
  def create_continuation_task(original_task, next_step, additional_input \\ %{}) do
    # Build correlation key based on original task
    base_key = original_task.correlation_key || to_string(original_task.id)
    continuation_key = "#{base_key}:#{next_step}"

    create_agent_task(
      original_task.user_id,
      next_step,
      Map.merge(original_task.input, additional_input),
      %{"original_task_id" => original_task.id, "step" => next_step},
      continuation_key
    )
  end

  @doc """
  Get active tasks for a user that may need attention.
  """
  def get_active_tasks(user_id) do
    Tasks.list_tasks_by_status(user_id, "running")
    |> Enum.concat(Tasks.list_tasks_by_status(user_id, "waiting"))
    |> Enum.filter(&is_task_active?/1)
  end

  @doc """
  Get task status and next actions.
  """
  def get_task_status(task) do
    case task.status do
      "queued" ->
        {:waiting, "Task is queued for execution"}

      "running" ->
        {:running, "Task is currently running"}

      "waiting" ->
        next_wait = get_in(task.state, ["next_wait"])
        {:waiting, "Task is waiting for: #{next_wait}"}

      "done" ->
        {:completed, task.result}

      "failed" ->
        {:failed, task.error}

      _ ->
        {:unknown, "Unknown task status: #{task.status}"}
    end
  end

  # Private helpers

  defp generate_correlation_key(user_id, kind, input) do
    # Generate a correlation key based on user, task kind, and input
    content = "#{user_id}:#{kind}:#{Jason.encode!(input)}"
    :crypto.hash(:sha256, content) |> Base.encode16(case: :lower)
  end

  defp get_correlation_key_from_event(event_data) do
    Map.get(event_data, "correlation_key")
  end

  defp handle_task_resumption(task, event_data) do
    try do
      # Mark task as running
      Tasks.mark_task_running(task)

      # Delegate to the appropriate handler based on task kind
      case task.kind do
        "schedule_meeting" ->
          handle_schedule_meeting_resumption(task, event_data)

        "send_email" ->
          handle_send_email_resumption(task, event_data)

        "create_contact" ->
          handle_create_contact_resumption(task, event_data)

        _ ->
          Logger.warning("Unknown task kind for resumption: #{task.kind}")
          Tasks.mark_task_failed(task, "Unknown task kind: #{task.kind}")
      end
    rescue
      e ->
        Logger.error("Task resumption failed: #{inspect(e)}")
        Tasks.mark_task_failed(task, "Resumption failed: #{Exception.message(e)}")
    end
  end

  defp handle_schedule_meeting_resumption(task, event_data) do
    case event_data do
      %{"type" => "confirmation", "event_id" => event_id} ->
        # Meeting confirmed, add notes and follow up
        Tasks.mark_task_done(task, %{
          "event_id" => event_id,
          "confirmed" => true,
          "completed_at" => DateTime.to_iso8601(DateTime.utc_now())
        })

        # Maybe add note to contact about confirmed meeting
        maybe_add_meeting_note(task.user_id, event_id, task.input)

      %{"type" => "cancellation", "event_id" => event_id} ->
        # Meeting cancelled
        Tasks.mark_task_done(task, %{
          "event_id" => event_id,
          "cancelled" => true,
          "completed_at" => DateTime.to_iso8601(DateTime.utc_now())
        })

      _ ->
        Tasks.mark_task_failed(task, "Invalid meeting resumption event")
    end
  end

  defp handle_send_email_resumption(task, event_data) do
    case event_data do
      %{"type" => "reply", "message_id" => message_id, "from" => from_email} ->
        # Email reply received
        Tasks.mark_task_done(task, %{
          "reply_received" => true,
          "message_id" => message_id,
          "from" => from_email,
          "completed_at" => DateTime.to_iso8601(DateTime.utc_now())
        })

        # Maybe trigger follow-up actions
        maybe_trigger_email_follow_up(task.user_id, task, event_data)

      _ ->
        Tasks.mark_task_failed(task, "Invalid email resumption event")
    end
  end

  defp handle_create_contact_resumption(task, event_data) do
    case event_data do
      %{"type" => "contact_created", "contact_id" => contact_id} ->
        # Contact successfully created
        Tasks.mark_task_done(task, %{
          "contact_id" => contact_id,
          "created" => true,
          "completed_at" => DateTime.to_iso8601(DateTime.utc_now())
        })

      _ ->
        Tasks.mark_task_failed(task, "Invalid contact creation resumption event")
    end
  end

  defp extract_gmail_correlation_key(event_data) do
    # Try to extract correlation key from Gmail event headers or metadata
    headers = Map.get(event_data, "headers", %{})
    custom_headers = Map.get(headers, "x-custom-headers", %{})
    Map.get(custom_headers, "x-correlation-key")
  end

  defp extract_calendar_correlation_key(event_data) do
    # Try to extract correlation key from calendar event description or extended properties
    description = Map.get(event_data, "description", "")
    extended_properties = Map.get(event_data, "extendedProperties", %{})

    # Look for correlation key in description
    if String.contains?(description, "correlation-key:") do
      [_full, key] = String.split(description, "correlation-key:")
      String.trim(key)
    else
      Map.get(extended_properties, "correlationKey")
    end
  end

  defp extract_hubspot_correlation_key(event_data) do
    # Try to extract correlation key from HubSpot event metadata
    metadata = Map.get(event_data, "metadata", %{})
    Map.get(metadata, "correlation_key")
  end

  defp handle_gmail_fallback(user_id, event_data) do
    # Try to match by thread ID or message ID
    thread_id = Map.get(event_data, "threadId")
    message_id = Map.get(event_data, "messageId")

    cond do
      thread_id ->
        find_task_by_thread_id(user_id, thread_id, event_data)

      message_id ->
        find_task_by_message_id(user_id, message_id, event_data)

      true ->
        Logger.warning("Could not find correlation key for Gmail event")
        {:error, :no_correlation_key}
    end
  end

  defp handle_calendar_fallback(user_id, event_data) do
    # Try to match by event ID
    event_id = Map.get(event_data, "eventId")

    if event_id do
      find_task_by_event_id(user_id, event_id, event_data)
    else
      Logger.warning("Could not find correlation key for Calendar event")
      {:error, :no_correlation_key}
    end
  end

  defp handle_hubspot_fallback(user_id, event_data) do
    # Try to match by object ID
    object_id = Map.get(event_data, "objectId")

    if object_id do
      find_task_by_object_id(user_id, object_id, event_data)
    else
      Logger.warning("Could not find correlation key for HubSpot event")
      {:error, :no_correlation_key}
    end
  end

  defp find_task_by_thread_id(user_id, thread_id, event_data) do
    # Look for tasks that might be related to this thread
    active_tasks = get_active_tasks(user_id)

    case Enum.find(active_tasks, fn task ->
           task_input = task.input || %{}
           Map.get(task_input, "thread_id") == thread_id
         end) do
      nil -> {:error, :task_not_found}
      task -> handle_task_resumption(task, event_data)
    end
  end

  defp find_task_by_message_id(_user_id, _message_id, _event_data) do
    # Implementation would search for tasks related to specific message
    {:error, :not_implemented}
  end

  defp find_task_by_event_id(_user_id, _event_id, _event_data) do
    # Implementation would search for tasks related to specific event
    {:error, :not_implemented}
  end

  defp find_task_by_object_id(_user_id, _object_id, _event_data) do
    # Implementation would search for tasks related to specific object
    {:error, :not_implemented}
  end

  defp is_task_active?(task) do
    # Check if task is still active (not too old)
    max_age_days = 7
    DateTime.diff(DateTime.utc_now(), task.inserted_at) <= max_age_days * 24 * 3600
  end

  # 24 hours
  defp get_wait_timeout("schedule_meeting"), do: 24 * 3600
  # 7 days
  defp get_wait_timeout("send_email"), do: 7 * 24 * 3600
  # 1 hour
  defp get_wait_timeout("create_contact"), do: 3600
  # 1 hour default
  defp get_wait_timeout(_), do: 3600

  defp maybe_add_meeting_note(user_id, event_id, task_input) do
    # This would add a note to the relevant contact about the meeting
    Logger.info("Adding meeting note for event #{event_id}")
  end

  defp maybe_trigger_email_follow_up(user_id, task, event_data) do
    # This could trigger additional agent actions based on email reply
    Logger.info("Triggering email follow-up for task #{task.id}")
  end
end
