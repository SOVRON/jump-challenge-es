defmodule Jump.Gmail.Threads do
  @moduledoc """
  Manages email thread information and participant tracking.
  """

  alias Jump.Gmail.Client
  alias Jump.Gmail.Processor
  alias Jump.RAG
  alias Jump.Sync
  require Logger

  @doc """
  Get complete thread information including all messages.
  """
  def get_thread(conn, thread_id, opts \\ []) do
    max_results = Keyword.get(opts, :max_results, 50)

    case Client.get_thread(conn, thread_id, max_results: max_results) do
      {:ok, thread} ->
        processed_thread = process_thread(thread)
        {:ok, processed_thread}

      {:error, reason} ->
        Logger.error("Failed to get thread #{thread_id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Update thread information from processed message.
  """
  def update_thread_from_message(user_id, processed_message) do
    thread_attrs = %{
      user_id: user_id,
      thread_id: processed_message.thread_id,
      last_history_id: processed_message.history_id,
      snippet: String.slice(processed_message.snippet, 0, 500),
      subject: processed_message.participants.subject,
      participants: extract_thread_participants(processed_message),
      last_message_at: processed_message.participants.date || processed_message.internal_date
    }

    Sync.upsert_email_thread(thread_attrs)
  end

  @doc """
  Get all participants in a thread.
  """
  def get_thread_participants(user_id, thread_id) do
    case Sync.get_email_thread_by_thread_id(user_id, thread_id) do
      nil -> []
      thread -> extract_participants_from_thread(thread)
    end
  end

  @doc """
  Get thread history for RAG context.
  """
  def get_thread_context(user_id, thread_id, opts \\ []) do
    max_messages = Keyword.get(opts, :max_messages, 10)

    chunks = RAG.get_chunks_by_source_id(user_id, "gmail", thread_id)

    # Group chunks by message and sort chronologically
    message_chunks =
      chunks
      |> Enum.group_by(fn chunk ->
        chunk.meta["message_id"] || chunk.source_id
      end)
      |> Enum.map(fn {message_id, chunks} ->
        %{
          message_id: message_id,
          chunks: chunks,
          date: get_message_date_from_chunks(chunks),
          from: get_message_sender_from_chunks(chunks),
          subject: get_message_subject_from_chunks(chunks)
        }
      end)
      |> Enum.sort_by(& &1.date, DateTime)
      |> Enum.take(-max_messages)

    %{
      thread_id: thread_id,
      messages: message_chunks,
      total_messages: length(message_chunks)
    }
  end

  @doc """
  Find threads related to specific participants.
  """
  def find_threads_by_participants(user_id, participant_emails, opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)

    # Get all threads for the user
    all_threads = Sync.list_email_threads(user_id)

    # Filter threads that involve the specified participants
    related_threads =
      all_threads
      |> Enum.filter(fn thread ->
        thread_participants = extract_participants_from_thread(thread)

        Enum.any?(participant_emails, fn email ->
          Enum.any?(thread_participants, fn participant ->
            participant_email = extract_email_from_participant(participant)
            participant_email == email
          end)
        end)
      end)
      |> Enum.sort_by(& &1.last_message_at, {:desc, DateTime})
      |> Enum.take(limit)

    related_threads
  end

  @doc """
  Get threads by subject pattern.
  """
  def find_threads_by_subject(user_id, subject_pattern, opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)

    all_threads = Sync.list_email_threads(user_id)

    matching_threads =
      all_threads
      |> Enum.filter(fn thread ->
        subject = thread.subject || ""
        String.contains?(String.downcase(subject), String.downcase(subject_pattern))
      end)
      |> Enum.sort_by(& &1.last_message_at, {:desc, DateTime})
      |> Enum.take(limit)

    matching_threads
  end

  @doc """
  Get recent threads for a user.
  """
  def get_recent_threads(user_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    days_back = Keyword.get(opts, :days_back, 30)

    cutoff_date = DateTime.add(DateTime.utc_now(), -days_back * 24 * 60 * 60, :second)

    Sync.list_email_threads(user_id)
    |> Enum.filter(fn thread ->
      DateTime.compare(thread.last_message_at, cutoff_date) != :lt
    end)
    |> Enum.sort_by(& &1.last_message_at, {:desc, DateTime})
    |> Enum.take(limit)
  end

  @doc """
  Extract conversation summary from thread.
  """
  def summarize_thread(user_id, thread_id, opts \\ []) do
    max_chunks = Keyword.get(opts, :max_chunks, 20)

    chunks = RAG.get_chunks_by_source_id(user_id, "gmail", thread_id)

    if Enum.empty?(chunks) do
      %{
        thread_id: thread_id,
        summary: "No content available for this thread",
        participants: [],
        message_count: 0
      }
    else
      # Sort chunks by date and limit
      sorted_chunks =
        chunks
        |> Enum.sort_by(&get_chunk_date/1, DateTime)
        |> Enum.take(-max_chunks)

      participants = extract_participants_from_chunks(sorted_chunks)
      message_count = extract_message_count_from_chunks(sorted_chunks)

      # Create a simple summary (in real implementation, this could use AI)
      summary = create_thread_summary(sorted_chunks)

      %{
        thread_id: thread_id,
        summary: summary,
        participants: participants,
        message_count: message_count,
        subject: get_thread_subject_from_chunks(sorted_chunks),
        last_message_date: get_last_message_date_from_chunks(sorted_chunks)
      }
    end
  end

  # Private helper functions

  defp process_thread(thread) do
    messages = thread.messages || []

    processed_messages =
      messages
      |> Enum.map(&Processor.process_message/1)
      |> Enum.sort_by(&get_message_date/1, DateTime)

    %{
      thread_id: thread.id,
      history_id: thread.historyId,
      messages: processed_messages,
      snippet: thread.snippet,
      total_messages: length(processed_messages),
      participants: extract_thread_participants_from_messages(processed_messages),
      subject: get_thread_subject(processed_messages),
      last_message_date: get_last_message_date(processed_messages)
    }
  end

  defp extract_thread_participants(processed_message) do
    all_addresses = Jump.Gmail.Processor.extract_all_addresses(processed_message)

    %{
      from: processed_message.participants.from,
      to: processed_message.participants.to,
      cc: processed_message.participants.cc,
      all: all_addresses
    }
  end

  defp extract_thread_participants_from_messages(messages) do
    all_participants =
      messages
      |> Enum.flat_map(&Jump.Gmail.Processor.extract_all_addresses/1)
      |> Enum.uniq()

    %{
      senders: Enum.map(messages, & &1.participants.from) |> Enum.uniq(),
      all: all_participants
    }
  end

  defp extract_participants_from_thread(thread) do
    case thread.participants do
      nil ->
        []

      participants when is_map(participants) ->
        Map.get(participants, "all", []) || Map.get(participants, :all, [])

      _ ->
        []
    end
  end

  defp extract_participants_from_chunks(chunks) do
    chunks
    |> Enum.flat_map(fn chunk ->
      case chunk.meta do
        %{"participants" => participants} -> participants
        _ -> []
      end
    end)
    |> Enum.uniq()
  end

  defp extract_email_from_participant(participant) do
    case participant do
      %{email: email} -> email
      email when is_binary(email) -> email
      _ -> ""
    end
  end

  defp get_message_date(message) do
    message.participants.date || message.internal_date || DateTime.utc_now()
  end

  defp get_chunk_date(chunk) do
    chunk.inserted_at || DateTime.utc_now()
  end

  defp get_message_sender_from_chunks(chunks) do
    case List.first(chunks) do
      nil ->
        nil

      chunk ->
        case chunk.meta do
          %{"from" => from} -> from
          _ -> nil
        end
    end
  end

  defp get_message_subject_from_chunks(chunks) do
    case List.first(chunks) do
      nil ->
        ""

      chunk ->
        case chunk.meta do
          %{"subject" => subject} -> subject || ""
          _ -> ""
        end
    end
  end

  defp get_message_date_from_chunks(chunks) do
    case List.first(chunks) do
      nil -> DateTime.utc_now()
      chunk -> get_chunk_date(chunk)
    end
  end

  defp extract_message_count_from_chunks(chunks) do
    chunks
    |> Enum.map(fn chunk ->
      case chunk.meta do
        %{"message_id" => message_id} -> message_id
        %{"source_id" => source_id} -> source_id
        _ -> chunk.source_id
      end
    end)
    |> Enum.uniq()
    |> length()
  end

  defp get_thread_subject(messages) do
    case List.first(messages) do
      nil -> ""
      message -> message.participants.subject || ""
    end
  end

  defp get_thread_subject_from_chunks(chunks) do
    case List.last(chunks) do
      nil ->
        ""

      chunk ->
        case chunk.meta do
          %{"subject" => subject} -> subject || ""
          _ -> ""
        end
    end
  end

  defp get_last_message_date(messages) do
    case List.last(messages) do
      nil -> DateTime.utc_now()
      message -> get_message_date(message)
    end
  end

  defp get_last_message_date_from_chunks(chunks) do
    case List.last(chunks) do
      nil -> DateTime.utc_now()
      chunk -> get_chunk_date(chunk)
    end
  end

  defp create_thread_summary(chunks) do
    # Simple summary based on first and last chunks
    first_chunk = List.first(chunks)
    last_chunk = List.last(chunks)

    first_content = first_chunk && String.slice(first_chunk.text, 0, 100)
    last_content = last_chunk && String.slice(last_chunk.text, 0, 100)

    message_count = extract_message_count_from_chunks(chunks)
    participants = extract_participants_from_chunks(chunks)

    "Thread with #{message_count} messages between #{length(participants)} participants. " <>
      "Started with: #{first_content || "No content"}. " <>
      "Latest: #{last_content || "No content"}."
  end

  # Helper functions for thread operations

  @doc """
  Archive a thread (mark as processed/read).
  """
  def archive_thread(conn, thread_id) do
    # Add "ARCHIVED" label or remove "INBOX" label
    Client.modify_message_labels(conn, thread_id, [], ["INBOX"])
  end

  @doc """
  Mark thread as important.
  """
  def mark_thread_important(conn, thread_id) do
    # Add "IMPORTANT" label
    Client.modify_message_labels(conn, thread_id, ["IMPORTANT"], [])
  end

  @doc """
  Add custom label to thread.
  """
  def label_thread(conn, thread_id, label) do
    Client.modify_message_labels(conn, thread_id, [label], [])
  end

  @doc """
  Remove label from thread.
  """
  def unlabel_thread(conn, thread_id, label) do
    Client.modify_message_labels(conn, thread_id, [], [label])
  end
end
