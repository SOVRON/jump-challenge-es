defmodule Mix.Tasks.Test.Rag do
  @moduledoc """
  Test RAG chunking and embedding operations.

  Usage:
    mix test.rag stats                                    # Show chunk statistics
    mix test.rag chunks --source gmail --limit 5          # View sample chunks
    mix test.rag import gmail                             # Import & chunk Gmail
    mix test.rag import hubspot                           # Import & chunk HubSpot
    mix test.rag import calendar                          # Import & chunk Calendar
    mix test.rag search "baseball"                        # Test vector search
    mix test.rag clear                                    # Delete all chunks (use carefully!)
  """

  use Mix.Task
  require Logger

  alias Jump.{Accounts, Repo, RAG}
  alias Jump.RAG.{Chunk, Search}
  alias Jump.Workers.{ImportGmailMailbox, ImportHubspotContacts}
  import Ecto.Query

  @shortdoc "Test RAG chunking and search operations"

  def run(args) do
    # Ensure the application and all dependencies are started
    Application.ensure_all_started(:jump)

    case args do
      ["stats" | opts] -> show_stats(opts)
      ["chunks" | opts] -> view_chunks(opts)
      ["import", "gmail" | opts] -> import_gmail(opts)
      ["import", "hubspot" | opts] -> import_hubspot(opts)
      ["import", "calendar" | opts] -> import_calendar(opts)
      ["search", query | opts] -> test_search(query, opts)
      ["clear" | opts] -> clear_chunks(opts)
      _ -> show_help()
    end
  end

  defp show_stats(opts) do
    user_id = get_user_id_from_opts(opts)

    IO.puts("\nRAG Chunk Statistics (User ID: #{user_id})\n")

    # Total chunks
    total_chunks =
      Repo.one(
        from c in Chunk,
          where: c.user_id == ^user_id,
          select: count(c.id)
      )

    IO.puts("Total chunks: #{total_chunks}")

    # Chunks by source
    chunks_by_source =
      Repo.all(
        from c in Chunk,
          where: c.user_id == ^user_id,
          group_by: c.source,
          select: {c.source, count(c.id)}
      )

    IO.puts("\nChunks by source:")

    Enum.each(chunks_by_source, fn {source, count} ->
      IO.puts("  #{source}: #{count}")
    end)

    # Chunks with embeddings
    chunks_with_embeddings =
      Repo.one(
        from c in Chunk,
          where: c.user_id == ^user_id and not is_nil(c.embedding),
          select: count(c.id)
      )

    chunks_without_embeddings = total_chunks - chunks_with_embeddings

    IO.puts("\nEmbedding status:")
    IO.puts("  With embeddings: #{chunks_with_embeddings}")
    IO.puts("  Without embeddings: #{chunks_without_embeddings}")

    if chunks_without_embeddings > 0 do
      IO.puts("\n⚠️  #{chunks_without_embeddings} chunks are missing embeddings!")
      IO.puts("  Run embedding workers to generate them.")
    end

    # Recent chunks
    recent_chunk =
      Repo.one(
        from c in Chunk,
          where: c.user_id == ^user_id,
          order_by: [desc: c.inserted_at],
          limit: 1,
          select: c.inserted_at
      )

    if recent_chunk do
      IO.puts("\nMost recent chunk: #{recent_chunk}")
    end
  end

  defp view_chunks(opts) do
    user_id = get_user_id_from_opts(opts)

    source =
      if Enum.member?(opts, "--source") do
        idx = Enum.find_index(opts, &(&1 == "--source"))
        Enum.at(opts, idx + 1)
      end

    limit =
      if Enum.member?(opts, "--limit") do
        idx = Enum.find_index(opts, &(&1 == "--limit"))
        String.to_integer(Enum.at(opts, idx + 1))
      else
        5
      end

    IO.puts("\nSample Chunks (User ID: #{user_id})\n")

    query =
      from c in Chunk,
        where: c.user_id == ^user_id,
        order_by: [desc: c.inserted_at],
        limit: ^limit

    query =
      if source do
        from c in query, where: c.source == ^source
      else
        query
      end

    chunks = Repo.all(query)

    if Enum.empty?(chunks) do
      IO.puts("No chunks found.")
    else
      Enum.each(chunks, fn chunk ->
        IO.puts("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        IO.puts("ID: #{chunk.id}")
        IO.puts("Source: #{chunk.source} (#{chunk.source_id})")
        if chunk.person_name, do: IO.puts("Person: #{chunk.person_name}")
        if chunk.person_email, do: IO.puts("Email: #{chunk.person_email}")
        IO.puts("Has embedding: #{if chunk.embedding, do: "Yes", else: "No"}")
        IO.puts("Created: #{chunk.inserted_at}")
        IO.puts("\nText preview:")
        IO.puts(String.slice(chunk.text, 0, 200) <> "...")
        IO.puts("")
      end)

      IO.puts("\nTotal shown: #{length(chunks)} chunks")
    end
  end

  defp import_gmail(opts) do
    user_id = get_user_id_from_opts(opts)

    IO.puts("\nImporting Gmail Messages (User ID: #{user_id})\n")
    IO.puts("This will fetch emails and create RAG chunks...")
    IO.puts("(This may take a while depending on mailbox size)\n")

    # Trigger the import worker
    case ImportGmailMailbox.perform(%Oban.Job{args: %{"user_id" => user_id}}) do
      :ok ->
        IO.puts("Gmail import completed!")
        IO.puts("\nRun 'mix test.rag stats' to see results.")

      {:error, reason} ->
        IO.puts("Import failed: #{inspect(reason)}")
    end
  end

  defp import_hubspot(opts) do
    user_id = get_user_id_from_opts(opts)

    IO.puts("\nImporting HubSpot Contacts (User ID: #{user_id})\n")
    IO.puts("This will fetch contacts and create RAG chunks...\n")

    # Trigger the import worker
    case ImportHubspotContacts.perform(%Oban.Job{args: %{"user_id" => user_id}}) do
      :ok ->
        IO.puts("HubSpot import completed!")
        IO.puts("\nRun 'mix test.rag stats' to see results.")

      {:error, reason} ->
        IO.puts("Import failed: #{inspect(reason)}")
    end
  end

  defp import_calendar(opts) do
    user_id = get_user_id_from_opts(opts)

    IO.puts("\nImporting Calendar Events (User ID: #{user_id})\n")
    IO.puts("This feature is not yet implemented.")
    IO.puts("Calendar events are typically synced via webhooks or periodic sync.")
  end

  defp test_search(query, opts) do
    user_id = get_user_id_from_opts(opts)

    limit =
      if Enum.member?(opts, "--limit") do
        idx = Enum.find_index(opts, &(&1 == "--limit"))
        String.to_integer(Enum.at(opts, idx + 1))
      else
        5
      end

    IO.puts("\nTesting Vector Search (User ID: #{user_id})\n")
    IO.puts("Query: \"#{query}\"")
    IO.puts("Limit: #{limit}\n")

    case Search.semantic_search(user_id, query, limit: limit) do
      {:ok, results} ->
        if Enum.empty?(results) do
          IO.puts("No results found.")
        else
          IO.puts("Found #{length(results)} results:\n")

          Enum.each(results, fn result ->
            IO.puts("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            IO.puts("Source: #{result.source} (#{result.source_id})")
            if result.person_name, do: IO.puts("Person: #{result.person_name}")
            IO.puts("Similarity: #{Float.round(result.similarity, 4)}")
            IO.puts("\nText:")
            IO.puts(String.slice(result.text, 0, 300) <> "...")
            IO.puts("")
          end)
        end

      {:error, reason} ->
        IO.puts("Search failed: #{inspect(reason)}")
    end
  end

  defp clear_chunks(opts) do
    user_id = get_user_id_from_opts(opts)

    IO.puts("\nWARNING: This will delete ALL chunks for user #{user_id}!")
    IO.puts("Press Ctrl+C to cancel, or wait 5 seconds to proceed...\n")

    Process.sleep(5000)

    {count, _} =
      Repo.delete_all(
        from c in Chunk,
          where: c.user_id == ^user_id
      )

    IO.puts("Deleted #{count} chunks")
  end

  defp get_user_id_from_opts(opts) do
    if Enum.member?(opts, "--user-id") do
      idx = Enum.find_index(opts, &(&1 == "--user-id"))
      Enum.at(opts, idx + 1) |> String.to_integer()
    else
      case Repo.one(from u in Accounts.User, select: u.id, limit: 1) do
        nil ->
          IO.puts("No users found in database. Please sign up first.")
          System.halt(1)

        id ->
          IO.puts("Using User ID: #{id}\n")
          id
      end
    end
  end

  defp show_help do
    IO.puts("""

    RAG Testing Commands

    View statistics:
      mix test.rag stats                        # Show chunk statistics
      mix test.rag stats --user-id 2            # For specific user

    View chunks:
      mix test.rag chunks                       # Show recent chunks
      mix test.rag chunks --limit 10            # Show 10 chunks
      mix test.rag chunks --source gmail        # Filter by source

    Import data:
      mix test.rag import gmail                 # Import Gmail messages
      mix test.rag import hubspot               # Import HubSpot contacts
      mix test.rag import calendar              # Import calendar events

    Test search:
      mix test.rag search "baseball"            # Test vector search
      mix test.rag search "AAPL stock" --limit 3

    Clear data:
      mix test.rag clear                        # Delete all chunks (careful!)

    """)
  end
end
