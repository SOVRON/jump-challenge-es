defmodule Jump.Messaging do
  @moduledoc """
  The Messaging context handles chat messages and conversations.
  """

  import Ecto.Query, warn: false
  alias Jump.Repo

  alias Jump.Messaging.{Conversation, Message}

  def list_messages(user_id) do
    Message
    |> where([m], m.user_id == ^user_id)
    |> order_by([m], desc: m.inserted_at)
    |> Repo.all()
  end

  def list_conversations(user_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 30)

    Message
    |> where([m], m.user_id == ^user_id)
    |> Repo.all()
    |> Enum.group_by(&conversation_group_key/1)
    |> Enum.map(&build_conversation_from_group/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.sort_by(&{&1.last_message_at, &1.id}, :desc)
    |> Enum.take(limit)
  end

  def list_messages_by_thread(user_id, thread_id) do
    Message
    |> where([m], m.user_id == ^user_id and m.thread_id == ^thread_id)
    |> order_by([m], asc: m.inserted_at, asc: m.id)
    |> Repo.all()
  end

  def list_messages_by_task(user_id, task_id) do
    Message
    |> where([m], m.user_id == ^user_id and m.task_id == ^task_id)
    |> order_by([m], asc: m.inserted_at, asc: m.id)
    |> Repo.all()
  end

  def get_message!(id), do: Repo.get!(Message, id)

  def create_message(attrs \\ %{}) do
    %Message{}
    |> Message.changeset(attrs)
    |> Repo.insert()
  end

  def update_message(%Message{} = message, attrs) do
    message
    |> Message.changeset(attrs)
    |> Repo.update()
  end

  def delete_message(%Message{} = message) do
    Repo.delete(message)
  end

  def change_message(%Message{} = message, attrs \\ %{}) do
    Message.changeset(message, attrs)
  end

  def create_user_message(user_id, content, thread_id \\ nil) do
    create_message(%{
      user_id: user_id,
      role: "user",
      content: content,
      thread_id: thread_id
    })
  end

  def create_assistant_message(user_id, content, thread_id \\ nil, task_id \\ nil) do
    create_message(%{
      user_id: user_id,
      role: "assistant",
      content: content,
      thread_id: thread_id,
      task_id: task_id
    })
  end

  def create_tool_message(
        user_id,
        tool_name,
        tool_args,
        tool_result,
        thread_id \\ nil,
        task_id \\ nil
      ) do
    create_message(%{
      user_id: user_id,
      role: "tool",
      tool_name: tool_name,
      tool_args: tool_args,
      tool_result: tool_result,
      thread_id: thread_id,
      task_id: task_id
    })
  end

  def get_thread_messages(user_id, thread_id, limit \\ 50) do
    Message
    |> where([m], m.user_id == ^user_id and m.thread_id == ^thread_id)
    |> order_by([m], asc: m.inserted_at, asc: m.id)
    |> limit(^limit)
    |> Repo.all()
  end

  def get_conversation_messages_by_id(user_id, conversation_id, opts \\ []) do
    with {:ok, scope, source_id} <- parse_conversation_identifier(conversation_id) do
      limit = Keyword.get(opts, :limit, 50)

      messages =
        case scope do
          :thread -> get_thread_messages(user_id, source_id, limit)
          :task -> list_messages_by_task(user_id, source_id)
          :orphan -> get_orphan_messages(user_id, source_id)
        end

      {:ok, messages}
    else
      :error -> {:error, :invalid_conversation}
    end
  end

  def get_conversation_summary(user_id, conversation_id) do
    with {:ok, scope, source_id} <- parse_conversation_identifier(conversation_id) do
      messages =
        case scope do
          :thread ->
            list_messages_by_thread(user_id, source_id)

          :task ->
            list_messages_by_task(user_id, source_id)

          :orphan ->
            get_orphan_messages(user_id, source_id)
        end

      if messages == [] do
        {:error, :not_found}
      else
        {:ok, build_conversation_from_group({{scope, source_id}, messages})}
      end
    else
      :error -> {:error, :invalid_conversation}
    end
  end

  def get_recent_messages(user_id, limit \\ 100) do
    Message
    |> where([m], m.user_id == ^user_id)
    |> order_by([m], desc: m.inserted_at)
    |> limit(^limit)
    |> Repo.all()
  end

  def parse_conversation_identifier("thread:" <> thread_id) when thread_id != "" do
    {:ok, :thread, thread_id}
  end

  def parse_conversation_identifier("task:" <> task_id) when task_id != "" do
    case Integer.parse(task_id) do
      {int_id, ""} -> {:ok, :task, int_id}
      _ -> :error
    end
  end

  def parse_conversation_identifier("message:" <> message_id) when message_id != "" do
    case Integer.parse(message_id) do
      {int_id, ""} -> {:ok, :orphan, int_id}
      _ -> :error
    end
  end

  def parse_conversation_identifier(_), do: :error

  defp conversation_group_key(%Message{thread_id: thread_id})
       when is_binary(thread_id) and thread_id != "" do
    {:thread, thread_id}
  end

  defp conversation_group_key(%Message{task_id: task_id}) when not is_nil(task_id) do
    {:task, task_id}
  end

  defp conversation_group_key(%Message{id: id}) do
    {:orphan, id}
  end

  defp build_conversation_from_group({{scope, source_id}, messages}) do
    sorted = Enum.sort_by(messages, &{&1.inserted_at, &1.id}, :desc)

    case sorted do
      [] ->
        nil

      [latest | _] ->
        %Conversation{
          id: conversation_identifier(scope, source_id),
          scope: scope,
          source_id: source_id,
          thread_id: if(scope == :thread, do: source_id, else: nil),
          task_id: if(scope == :task, do: source_id, else: nil),
          title: conversation_title(sorted),
          preview: message_preview(latest),
          last_message_at: latest.inserted_at,
          last_role: latest.role,
          messages_count: length(messages),
          participants: collect_participants(messages)
        }
    end
  end

  defp conversation_identifier(:thread, thread_id), do: "thread:#{thread_id}"
  defp conversation_identifier(:task, task_id), do: "task:#{task_id}"
  defp conversation_identifier(:orphan, message_id), do: "message:#{message_id}"

  defp conversation_title(messages) do
    messages
    |> Enum.find(&user_message?/1)
    |> case do
      %Message{content: content} when is_binary(content) and content != "" ->
        content
        |> collapse_whitespace()
        |> maybe_truncate(80)

      _ ->
        "Conversation"
    end
  end

  defp user_message?(%Message{role: "user", content: content})
       when is_binary(content) and content != "",
       do: true

  defp user_message?(_), do: false

  defp message_preview(%Message{role: "tool", tool_name: tool_name, tool_result: tool_result}) do
    summary =
      cond do
        is_map(tool_result) &&
            (Map.get(tool_result, "summary") || Map.get(tool_result, :summary)) ->
          Map.get(tool_result, "summary") || Map.get(tool_result, :summary)

        is_map(tool_result) &&
            (Map.get(tool_result, "status") || Map.get(tool_result, :status)) ->
          Map.get(tool_result, "status") || Map.get(tool_result, :status)

        is_binary(tool_result) ->
          tool_result

        true ->
          nil
      end

    base_text =
      summary ||
        if(tool_name, do: "#{tool_name} completed", else: "Tool call completed")

    base_text
    |> collapse_whitespace()
    |> maybe_truncate(120)
  end

  defp message_preview(%Message{content: content}) when is_binary(content) and content != "" do
    content
    |> collapse_whitespace()
    |> maybe_truncate(140)
  end

  defp message_preview(%Message{}), do: "..."

  defp collect_participants(messages) do
    messages
    |> Enum.filter(&(&1.role == "tool"))
    |> Enum.flat_map(fn
      %Message{tool_result: %{} = tool_result} ->
        cond do
          participants =
              Map.get(tool_result, "participants") || Map.get(tool_result, :participants) ->
            List.wrap(participants)

          person_email =
              Map.get(tool_result, "person_email") || Map.get(tool_result, :person_email) ->
            person_name =
              Map.get(tool_result, "person_name") || Map.get(tool_result, :person_name)

            Enum.reject([person_name, person_email], &is_nil/1)

          true ->
            []
        end

      _ ->
        []
    end)
    |> Enum.map(&to_string/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  defp get_orphan_messages(user_id, message_id) do
    Message
    |> where([m], m.user_id == ^user_id and m.id == ^message_id)
    |> order_by([m], asc: m.inserted_at, asc: m.id)
    |> Repo.all()
  end

  defp collapse_whitespace(text) when is_binary(text) do
    text
    |> String.trim()
    |> String.replace(~r/\s+/, " ")
  end

  defp maybe_truncate(text, max) when is_binary(text) and max > 0 do
    if String.length(text) <= max do
      text
    else
      String.slice(text, 0, max) <> "..."
    end
  end
end
