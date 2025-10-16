defmodule Jump.Workers.GmailHistorySync do
  @moduledoc """
  Oban worker for incremental Gmail synchronization using history API.
  """

  use Oban.Worker, queue: :sync, max_attempts: 3, unique: [period: 60]

  alias Jump.Gmail.Client
  alias Jump.Gmail.Processor
  alias Jump.Gmail.Chunker
  alias Jump.RAG
  alias Jump.Sync
  require Logger

  @max_history_results 100
  @rate_limit_delay_ms 200

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"user_id" => user_id}}) do
    Logger.info("Starting Gmail history sync for user #{user_id}")

    case Client.get_conn(user_id) do
      {:ok, conn} ->
        sync_user_history(conn, user_id)

      {:error, reason} ->
        Logger.error("Failed to get Gmail connection for user #{user_id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Private functions

  defp sync_user_history(conn, user_id) do
    case get_current_history_id(user_id) do
      {:ok, current_history_id} ->
        Logger.debug("Current history ID for user #{user_id}: #{current_history_id}")
        fetch_and_process_history(conn, user_id, current_history_id)

      {:error, :no_history_id} ->
        Logger.info("No history ID found for user #{user_id}, performing initial sync")
        perform_initial_sync(conn, user_id)

      {:error, reason} ->
        Logger.error("Failed to get current history ID for user #{user_id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp get_current_history_id(user_id) do
    case Sync.get_gmail_cursor(user_id) do
      nil -> {:error, :no_history_id}
      cursor -> {:ok, cursor.history_id}
    end
  end

  defp fetch_and_process_history(conn, user_id, history_id) do
    case Client.get_history(conn, history_id, max_results: @max_history_results) do
      {:ok,
       %{history: history_list, next_page_token: next_page_token, history_id: latest_history_id}} ->
        Logger.info("Found #{length(history_list)} history records for user #{user_id}")

        # Process history records
        process_history_records(conn, user_id, history_list)

        # Update cursor
        update_history_cursor(user_id, latest_history_id)

        # Schedule next page if available
        if next_page_token do
          schedule_next_page(user_id, next_page_token, latest_history_id)
        else
          Logger.info("Completed Gmail history sync for user #{user_id}")
        end

        :ok

      {:ok, %{history: []}} ->
        Logger.debug("No new history for user #{user_id}")
        :ok

      {:error, reason} ->
        Logger.error("Failed to get Gmail history for user #{user_id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp process_history_records(conn, user_id, history_list) do
    Enum.each(history_list, fn history_record ->
      :timer.sleep(@rate_limit_delay_ms)

      try do
        process_single_history_record(conn, user_id, history_record)
      rescue
        error ->
          Logger.error("Error processing history record: #{inspect(error)}")
      end
    end)
  end

  defp process_single_history_record(conn, user_id, %{
         "id" => history_id,
         "messagesAdded" => messages
       }) do
    Logger.debug("Processing #{length(messages)} added messages in history #{history_id}")

    Enum.each(messages, fn message_data ->
      message_id = get_in(message_data, ["message", "id"])
      process_message_update(conn, user_id, message_id, :added)
    end)
  end

  defp process_single_history_record(conn, user_id, %{"messagesDeleted" => messages}) do
    Logger.debug("Processing #{length(messages)} deleted messages in history")

    Enum.each(messages, fn message_data ->
      message_id = get_in(message_data, ["message", "id"])
      process_message_update(conn, user_id, message_id, :deleted)
    end)
  end

  defp process_single_history_record(conn, user_id, %{"labelsAdded" => label_changes}) do
    Logger.debug("Processing #{length(label_changes)} label additions")

    Enum.each(label_changes, fn label_change ->
      message_id = get_in(label_change, ["message", "id"])
      process_message_update(conn, user_id, message_id, :labels_changed)
    end)
  end

  defp process_single_history_record(conn, user_id, %{"labelsRemoved" => label_changes}) do
    Logger.debug("Processing #{length(label_changes)} label removals")

    Enum.each(label_changes, fn label_change ->
      message_id = get_in(label_change, ["message", "id"])
      process_message_update(conn, user_id, message_id, :labels_changed)
    end)
  end

  defp process_single_history_record(_conn, _user_id, history_record) do
    Logger.debug("Ignoring history record type: #{Map.keys(history_record)}")
  end

  defp process_message_update(conn, user_id, message_id, change_type) do
    case change_type do
      :deleted ->
        handle_message_deletion(user_id, message_id)

      :added ->
        handle_message_addition(conn, user_id, message_id)

      :labels_changed ->
        handle_message_label_change(user_id, message_id)
    end
  end

  defp handle_message_deletion(user_id, message_id) do
    Logger.debug("Handling deletion of message #{message_id}")

    # Delete chunks associated with this message
    case RAG.delete_chunks_by_source_id(user_id, "gmail", message_id) do
      {count, _} ->
        Logger.debug("Deleted #{count} chunks for message #{message_id}")

      error ->
        Logger.error("Failed to delete chunks for message #{message_id}: #{inspect(error)}")
    end
  end

  defp handle_message_addition(conn, user_id, message_id) do
    Logger.debug("Handling addition of message #{message_id}")

    # Check if message already exists
    existing_chunks = RAG.get_chunks_by_source_id(user_id, "gmail", message_id)

    if Enum.empty?(existing_chunks) do
      # Import the new message
      case Client.get_message(conn, message_id, format: "full", headers: true) do
        {:ok, message} ->
          process_new_message(user_id, message)

        {:error, reason} ->
          Logger.error("Failed to fetch new message #{message_id}: #{inspect(reason)}")
      end
    else
      Logger.debug("Message #{message_id} already exists, skipping")
    end
  end

  defp handle_message_label_change(user_id, message_id) do
    Logger.debug("Handling label change for message #{message_id}")

    # For now, we don't do anything special with label changes
    # In the future, this could trigger re-processing if important labels are added
  end

  defp process_new_message(user_id, message) do
    try do
      processed_message = Processor.process_message(message)

      # Update email thread information
      update_email_thread(user_id, processed_message)

      # Create chunks
      chunks = Chunker.create_rag_chunks(processed_message, user_id: user_id)

      if Enum.empty?(chunks) do
        Logger.warning("No chunks created for new message #{processed_message.message_id}")
      else
        # Store chunks and schedule embeddings
        store_chunks(user_id, chunks)

        Logger.info(
          "Created #{length(chunks)} chunks for new message #{processed_message.message_id}"
        )
      end

      :ok
    rescue
      error ->
        Logger.error("Error processing new message: #{inspect(error)}")
        {:error, error}
    end
  end

  defp update_email_thread(user_id, processed_message) do
    thread_attrs = %{
      user_id: user_id,
      thread_id: processed_message.thread_id,
      last_history_id: processed_message.history_id,
      snippet: String.slice(processed_message.snippet, 0, 500),
      subject: processed_message.participants.subject,
      participants: %{
        from: processed_message.participants.from,
        to: processed_message.participants.to,
        cc: processed_message.participants.cc,
        all: Jump.Gmail.Processor.extract_all_addresses(processed_message)
      },
      last_message_at: processed_message.participants.date || processed_message.internal_date
    }

    Sync.upsert_email_thread(thread_attrs)
  end

  defp store_chunks(user_id, chunks) do
    Enum.each(chunks, fn chunk_attrs ->
      case RAG.create_chunk(chunk_attrs) do
        {:ok, chunk} ->
          # Schedule embedding for this chunk
          schedule_embedding(chunk.id)

        {:error, reason} ->
          Logger.error("Failed to create chunk: #{inspect(reason)}")
      end
    end)
  end

  defp update_history_cursor(user_id, history_id) do
    cursor_attrs = %{
      user_id: user_id,
      history_id: history_id
    }

    Sync.upsert_gmail_cursor(cursor_attrs)
    Logger.debug("Updated history cursor for user #{user_id} to #{history_id}")
  end

  defp perform_initial_sync(conn, user_id) do
    # Get the current history ID from Gmail
    case Client.list_messages(conn, max_results: 1) do
      {:ok, %{messages: []}} ->
        Logger.info("No messages found for initial sync")
        :ok

      {:ok, %{messages: [first_message]}} ->
        # Use the history ID from the first message
        case Client.get_message(conn, first_message.id, format: "metadata") do
          {:ok, %{historyId: history_id}} ->
            update_history_cursor(user_id, history_id)
            Logger.info("Set initial history cursor for user #{user_id} to #{history_id}")
            :ok

          {:error, reason} ->
            Logger.error("Failed to get initial history ID: #{inspect(reason)}")
            {:error, reason}
        end

      {:error, reason} ->
        Logger.error("Failed to get initial message for history sync: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp schedule_next_page(user_id, page_token, latest_history_id) do
    %{"user_id" => user_id, "page_token" => page_token, "latest_history_id" => latest_history_id}
    |> __MODULE__.new(schedule_in: 2)
    |> Oban.insert()
  end

  defp schedule_embedding(chunk_id) do
    %{"chunk_id" => chunk_id}
    |> Jump.Workers.EmbedChunk.new(queue: :embed)
    |> Oban.insert()
  end

  # Helper functions for manual operations

  @doc """
  Force sync user's Gmail history.
  """
  def sync_user(user_id) do
    %{"user_id" => user_id}
    |> __MODULE__.new()
    |> Oban.insert()
  end

  @doc """
  Reset user's Gmail history cursor.
  """
  def reset_user_cursor(user_id) do
    case Sync.get_gmail_cursor(user_id) do
      nil -> :ok
      cursor -> Sync.delete_gmail_cursor(cursor)
    end
  end
end
