defmodule Jump.Workers.ImportGmailMailbox do
  @moduledoc """
  Oban worker for importing Gmail messages into the RAG pipeline.
  """

  use Oban.Worker, queue: :ingest, max_attempts: 3, unique: [period: 300]

  alias Jump.Gmail.Client
  alias Jump.Gmail.Processor
  alias Jump.Gmail.Chunker
  alias Jump.RAG
  alias Jump.Sync
  require Logger

  @import_window_months 24
  @messages_per_page 50
  @rate_limit_delay_ms 100

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"user_id" => user_id} = args}) do
    Logger.info("Starting Gmail import for user #{user_id}")

    case Client.get_conn(user_id) do
      {:ok, conn} ->
        query = build_import_query(args)
        import_messages(conn, user_id, query)

      {:error, reason} ->
        Logger.error("Failed to get Gmail connection for user #{user_id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"message_id" => message_id, "user_id" => user_id}}) do
    # Import a single message
    Logger.info("Importing single Gmail message #{message_id} for user #{user_id}")

    case Client.get_conn(user_id) do
      {:ok, conn} ->
        import_single_message(conn, user_id, message_id)

      {:error, reason} ->
        Logger.error("Failed to get Gmail connection for user #{user_id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Private functions

  defp build_import_query(args) do
    # Default: last 24 months
    date_query = build_date_query(args)

    # Additional filters (support both map and keyword list)
    label_query = get_arg(args, :label_query, "")
    search_query = get_arg(args, :search_query, "")

    queries =
      [date_query, label_query, search_query]
      |> Enum.filter(&(&1 != ""))
      |> Enum.join(" ")
  end

  defp build_date_query(args) do
    months = get_arg(args, :months, @import_window_months)
    cutoff_date = DateTime.add(DateTime.utc_now(), -months * 30 * 24 * 60 * 60, :second)
    date_string = DateTime.to_string(cutoff_date) |> String.slice(0, 10)
    "after:#{date_string}"
  end

  defp import_messages(conn, user_id, query) do
    case Client.list_messages(conn, query: query, max_results: @messages_per_page) do
      {:ok, %{messages: messages, next_page_token: next_page_token}} ->
        Logger.info("Found #{length(messages)} messages for initial page")

        # Process current page
        process_message_batch(conn, user_id, messages)

        # Schedule next page if available
        if next_page_token do
          schedule_next_page(user_id, query, next_page_token)
        else
          Logger.info("Completed Gmail import for user #{user_id}")
        end

        :ok

      {:ok, %{messages: []}} ->
        Logger.info("No messages found for user #{user_id} with query: #{query}")
        :ok

      {:error, reason} ->
        Logger.error("Failed to list messages for user #{user_id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Helper to get arg from either map or keyword list
  defp get_arg(args, key, default) when is_map(args) do
    Map.get(args, Atom.to_string(key), Map.get(args, key, default))
  end

  defp get_arg(args, key, default) when is_list(args) do
    Keyword.get(args, key, default)
  end

  defp process_message_batch(conn, user_id, messages) do
    Enum.each(messages, fn message ->
      # Add delay to respect rate limits
      :timer.sleep(@rate_limit_delay_ms)

      case import_single_message(conn, user_id, message.id) do
        :ok ->
          Logger.debug("Successfully imported message #{message.id}")

        {:error, reason} ->
          Logger.warning("Failed to import message #{message.id}: #{inspect(reason)}")
      end
    end)
  end

  defp import_single_message(conn, user_id, message_id) do
    case Client.get_message(conn, message_id, format: "full", headers: true) do
      {:ok, message} ->
        process_message(user_id, message)

      {:error, reason} ->
        Logger.error("Failed to get message #{message_id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp process_message(user_id, message) do
    try do
      # Process the message
      processed_message = Processor.process_message(message)

      # Update email thread information
      update_email_thread(user_id, processed_message)

      # Create chunks
      chunks = Chunker.create_rag_chunks(processed_message, user_id: user_id)

      if Enum.empty?(chunks) do
        Logger.warning("No chunks created for message #{processed_message.message_id}")
        :ok
      else
        # Store chunks in database
        store_chunks(user_id, chunks)

        Logger.info(
          "Created #{length(chunks)} chunks for message #{processed_message.message_id}"
        )

        :ok
      end
    rescue
      error ->
        Logger.error("Error processing message: #{inspect(error)}")
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

  defp schedule_next_page(user_id, query, page_token) do
    %{"user_id" => user_id, "query" => query, "page_token" => page_token}
    |> __MODULE__.new(schedule_in: 5)
    |> Oban.insert()
  end

  defp schedule_embedding(chunk_id) do
    %{"chunk_id" => chunk_id}
    |> Jump.Workers.EmbedChunk.new(queue: :embed)
    |> Oban.insert()
  end

  # Helper function for manual imports
  def import_user_mailbox(user_id, opts \\ []) do
    %{"user_id" => user_id}
    |> Map.merge(Enum.into(opts, %{}))
    |> __MODULE__.new()
    |> Oban.insert()
  end

  # Helper function for importing specific message
  def import_message(user_id, message_id) do
    %{"user_id" => user_id, "message_id" => message_id}
    |> __MODULE__.new()
    |> Oban.insert()
  end

  # Helper function for searching and importing
  def search_and_import(user_id, search_query, opts \\ []) do
    %{"user_id" => user_id, "search_query" => search_query}
    |> Map.merge(Enum.into(opts, %{}))
    |> __MODULE__.new()
    |> Oban.insert()
  end
end
