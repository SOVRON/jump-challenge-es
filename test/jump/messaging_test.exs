defmodule Jump.MessagingTest do
  use Jump.DataCase, async: true

  @moduletag :db

  alias Jump.Agent
  alias Jump.Messaging

  describe "conversations" do
    test "list_conversations returns thread summaries ordered by latest activity" do
      user = user_fixture()
      another_user = user_fixture()
      thread_id = Agent.generate_thread_id()

      user_message_fixture(user, "Tell me about Sara's recent emails.", thread_id)
      Process.sleep(5)
      assistant_message_fixture(user, "Sara mentioned her kid's baseball practice.", thread_id)
      user_message_fixture(another_user, "Other user message", Agent.generate_thread_id())

      [conversation | _] = Messaging.list_conversations(user.id)

      assert conversation.thread_id == thread_id
      assert conversation.id == "thread:#{thread_id}"
      assert conversation.messages_count == 2
      assert conversation.preview =~ "baseball"
    end

    test "list_conversations falls back to single-message conversation when thread is missing" do
      user = user_fixture()
      message = user_message_fixture(user, "Single log without thread")

      [conversation] = Messaging.list_conversations(user.id)

      assert conversation.id == "message:#{message.id}"
      assert conversation.messages_count == 1
      assert conversation.preview =~ "Single log"
    end

    test "get_conversation_messages_by_id returns ordered thread messages" do
      user = user_fixture()
      thread_id = Agent.generate_thread_id()

      msg1 = user_message_fixture(user, "First turn", thread_id)
      msg2 = assistant_message_fixture(user, "Second turn", thread_id)

      {:ok, messages} = Messaging.get_conversation_messages_by_id(user.id, "thread:#{thread_id}")

      assert Enum.map(messages, & &1.id) == [msg1.id, msg2.id]
    end
  end
end
