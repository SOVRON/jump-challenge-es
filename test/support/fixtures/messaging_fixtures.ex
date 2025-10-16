defmodule Jump.MessagingFixtures do
  @moduledoc """
  Helpers for creating messaging entities in tests.
  """

  alias Jump.Messaging

  def user_message_fixture(user, content \\ "Hello from user", thread_id \\ nil) do
    {:ok, message} = Messaging.create_user_message(user.id, content, thread_id)
    message
  end

  def assistant_message_fixture(
        user,
        content \\ "Hello from assistant",
        thread_id \\ nil,
        task_id \\ nil
      ) do
    {:ok, message} = Messaging.create_assistant_message(user.id, content, thread_id, task_id)
    message
  end

  def tool_message_fixture(user, attrs \\ %{}) do
    defaults = %{
      tool_name: "rag.search",
      tool_args: %{"query" => "example"},
      tool_result: %{"summary" => "Summarized content."},
      thread_id: nil,
      task_id: nil
    }

    merged = Map.merge(defaults, attrs)

    {:ok, message} =
      Messaging.create_tool_message(
        user.id,
        merged.tool_name,
        merged.tool_args,
        merged.tool_result,
        merged.thread_id,
        merged.task_id
      )

    message
  end
end
