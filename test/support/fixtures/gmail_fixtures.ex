defmodule Jump.GmailFixtures do
  @moduledoc """
  Fixtures for Gmail-related tests.
  """

  @doc """
  Generate a Gmail message fixture
  """
  def gmail_message_fixture(attrs \\ %{}) do
    attrs =
      Enum.into(attrs, %{
        "id" => "msg_#{:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)}",
        "threadId" => "thread_1",
        "labelIds" => ["INBOX"],
        "snippet" => "Test message snippet",
        "internalDate" => to_string(DateTime.to_unix(DateTime.utc_now(), :millisecond)),
        "payload" => %{
          "mimeType" => "text/plain",
          "headers" => [
            %{"name" => "From", "value" => "sender@example.com"},
            %{"name" => "To", "value" => "recipient@example.com"},
            %{"name" => "Subject", "value" => "Test Subject"},
            %{"name" => "Date", "value" => DateTime.to_string(DateTime.utc_now())}
          ],
          "body" => %{"size" => 100, "data" => "VGVzdCBtZXNzYWdlIGJvZHk="}
        },
        "sizeEstimate" => 1000
      })

    Map.merge(
      %{
        "id" => attrs["id"],
        "threadId" => attrs["threadId"],
        "labelIds" => attrs["labelIds"],
        "snippet" => attrs["snippet"],
        "internalDate" => attrs["internalDate"],
        "payload" => attrs["payload"],
        "sizeEstimate" => attrs["sizeEstimate"]
      },
      attrs
    )
  end

  @doc """
  Generate a Gmail thread fixture
  """
  def gmail_thread_fixture(attrs \\ %{}) do
    attrs =
      Enum.into(attrs, %{
        "id" => "thread_#{:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)}",
        "snippet" => "Thread snippet",
        "historyId" => "123456",
        "messages" => [gmail_message_fixture()]
      })

    %{
      "id" => attrs["id"],
      "snippet" => attrs["snippet"],
      "historyId" => attrs["historyId"],
      "messages" => attrs["messages"]
    }
  end

  @doc """
  Generate a Gmail history response fixture
  """
  def gmail_history_fixture(attrs \\ %{}) do
    attrs =
      Enum.into(attrs, %{
        "history" => [
          %{
            "id" => "123",
            "messages" => [gmail_message_fixture()],
            "labelsAdded" => [%{"message" => gmail_message_fixture(), "labelIds" => ["INBOX"]}],
            "labelsRemoved" => []
          }
        ],
        "historyId" => "123456"
      })

    %{
      "history" => attrs["history"],
      "historyId" => attrs["historyId"]
    }
  end

  @doc """
  Generate a processed Gmail message for RAG chunking
  """
  def processed_gmail_message_fixture(attrs \\ %{}) do
    attrs =
      Enum.into(attrs, %{
        "message_id" => "msg_123",
        "thread_id" => "thread_1",
        "from" => "sender@example.com",
        "to" => ["recipient@example.com"],
        "subject" => "Test Subject",
        "body_text" => "This is a test message body",
        "body_html" => "<p>This is a test message body</p>",
        "date" => DateTime.utc_now(),
        "labels" => ["INBOX"]
      })

    %{
      "message_id" => attrs["message_id"],
      "thread_id" => attrs["thread_id"],
      "from" => attrs["from"],
      "to" => attrs["to"],
      "subject" => attrs["subject"],
      "body_text" => attrs["body_text"],
      "body_html" => attrs["body_html"],
      "date" => attrs["date"],
      "labels" => attrs["labels"]
    }
  end
end
