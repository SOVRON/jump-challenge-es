defmodule Mix.Tasks.Test.Gmail do
  @moduledoc """
  Test Gmail API functions.

  Usage:
    mix test.gmail list                                    # List recent messages
    mix test.gmail list --max 20                           # List 20 messages
    mix test.gmail search "from:user@example.com"          # Search messages
    mix test.gmail send --to "user@example.com" --subject "Test" --body "<p>Hello</p>"
    mix test.gmail get <message_id>                        # Get specific message
  """

  use Mix.Task
  require Logger

  alias Jump.{Accounts, Gmail.Client, Repo}
  import Ecto.Query

  @shortdoc "Test Gmail API functions"

  def run(args) do
    # Ensure the application and all dependencies are started
    Application.ensure_all_started(:jump)

    case args do
      ["list" | opts] -> list_messages(opts)
      ["search", query | opts] -> search_messages(query, opts)
      ["send" | opts] -> send_message(opts)
      ["get", message_id] -> get_message(message_id)
      ["labels"] -> list_labels()
      _ -> show_help()
    end
  end

  defp list_messages(opts) do
    user_id = get_user_id_from_opts(opts)

    max_results =
      if Enum.member?(opts, "--max") do
        max_idx = Enum.find_index(opts, &(&1 == "--max"))
        String.to_integer(Enum.at(opts, max_idx + 1))
      else
        10
      end

    IO.puts("\nListing Gmail Messages (max: #{max_results})\n")

    case Client.get_conn(user_id) do
      {:ok, conn} ->
        case Client.list_messages(conn, max_results: max_results) do
          {:ok, response} ->
            if Enum.empty?(response.messages || []) do
              IO.puts("  No messages found")
            else
              # Fetch details for each message
              Enum.each(response.messages, fn msg ->
                case Client.get_message(conn, msg.id) do
                  {:ok, message} ->
                    from = get_header(message, "From")
                    subject = get_header(message, "Subject")
                    date = get_header(message, "Date")

                    IO.puts("  ✉️  #{subject || "(No subject)"}")
                    IO.puts("     From: #{from}")
                    IO.puts("     Date: #{date}")
                    IO.puts("     ID: #{message.id}")
                    IO.puts("")

                  {:error, _} ->
                    IO.puts("  ⚠️  Could not fetch message #{msg.id}")
                end
              end)

              IO.puts("Total: #{length(response.messages)} messages")
            end

          {:error, reason} ->
            IO.puts("Failed: #{inspect(reason)}")
        end

      {:error, reason} ->
        IO.puts("No OAuth connection: #{inspect(reason)}")
    end
  end

  defp search_messages(query, opts) do
    user_id = get_user_id_from_opts(opts)

    max_results =
      if Enum.member?(opts, "--max") do
        max_idx = Enum.find_index(opts, &(&1 == "--max"))
        String.to_integer(Enum.at(opts, max_idx + 1))
      else
        10
      end

    IO.puts("\n🔍 Searching Gmail: \"#{query}\" (max: #{max_results})\n")

    case Client.get_conn(user_id) do
      {:ok, conn} ->
        case Client.search_messages(conn, query, max_results: max_results) do
          {:ok, response} ->
            if Enum.empty?(response.messages || []) do
              IO.puts("  No messages found")
            else
              Enum.each(response.messages, fn msg ->
                case Client.get_message(conn, msg.id) do
                  {:ok, message} ->
                    from = get_header(message, "From")
                    subject = get_header(message, "Subject")

                    IO.puts("  ✉️  #{subject || "(No subject)"}")
                    IO.puts("     From: #{from}")
                    IO.puts("     ID: #{message.id}")
                    IO.puts("")

                  {:error, _} ->
                    :ok
                end
              end)

              IO.puts("Found: #{length(response.messages)} messages")
            end

          {:error, reason} ->
            IO.puts("Failed: #{inspect(reason)}")
        end

      {:error, reason} ->
        IO.puts("No OAuth connection: #{inspect(reason)}")
    end
  end

  defp send_message(opts) do
    user_id = get_user_id_from_opts(opts)

    to_idx = Enum.find_index(opts, &(&1 == "--to"))
    subject_idx = Enum.find_index(opts, &(&1 == "--subject"))
    body_idx = Enum.find_index(opts, &(&1 == "--body"))

    unless to_idx && subject_idx && body_idx do
      IO.puts("--to, --subject, and --body are required")
    else
      to = Enum.at(opts, to_idx + 1) |> String.split(",")
      subject = Enum.at(opts, subject_idx + 1)
      body = Enum.at(opts, body_idx + 1)

      text_body =
        if Enum.member?(opts, "--text") do
          text_idx = Enum.find_index(opts, &(&1 == "--text"))
          Enum.at(opts, text_idx + 1)
        end

      IO.puts("\n📤 Sending Email\n")
      IO.puts("  To: #{Enum.join(to, ", ")}")
      IO.puts("  Subject: #{subject}")

      IO.puts(
        "  Body: #{String.slice(body, 0, 50)}#{if String.length(body) > 50, do: "...", else: ""}"
      )

      IO.puts("")

      case Jump.Gmail.Composer.send_email(user_id, to, subject, body, text_body, nil, []) do
        {:ok, message_id} ->
          IO.puts("Email sent successfully!")
          IO.puts("  Message ID: #{message_id}")

        {:error, reason} ->
          IO.puts("❌ Failed: #{inspect(reason)}")
      end
    end
  end

  defp get_message(message_id) do
    user_id = get_user_id_from_opts([])

    IO.puts("\nGetting Message: #{message_id}\n")

    case Client.get_conn(user_id) do
      {:ok, conn} ->
        case Client.get_message(conn, message_id) do
          {:ok, message} ->
            from = get_header(message, "From")
            to = get_header(message, "To")
            subject = get_header(message, "Subject")
            date = get_header(message, "Date")

            IO.puts("  From: #{from}")
            IO.puts("  To: #{to}")
            IO.puts("  Subject: #{subject}")
            IO.puts("  Date: #{date}")
            IO.puts("  ID: #{message.id}")
            IO.puts("  Thread ID: #{message.threadId}")
            IO.puts("  Labels: #{Enum.join(message.labelIds || [], ", ")}")

            # Try to get body
            if message.payload do
              body = extract_body(message.payload)

              if body do
                IO.puts("\n  Body Preview:")
                IO.puts("  " <> String.slice(body, 0, 200))
              end
            end

          {:error, reason} ->
            IO.puts("Failed: #{inspect(reason)}")
        end

      {:error, reason} ->
        IO.puts("No OAuth connection: #{inspect(reason)}")
    end
  end

  defp list_labels do
    user_id = get_user_id_from_opts([])

    IO.puts("\n🏷️  Listing Gmail Labels\n")

    case Client.get_conn(user_id) do
      {:ok, conn} ->
        case Client.list_labels(conn) do
          {:ok, response} ->
            Enum.each(response.labels || [], fn label ->
              IO.puts("  • #{label.name} (#{label.id})")
            end)

            IO.puts("\nTotal: #{length(response.labels || [])} labels")

          {:error, reason} ->
            IO.puts("Failed: #{inspect(reason)}")
        end

      {:error, reason} ->
        IO.puts("No OAuth connection: #{inspect(reason)}")
    end
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
          IO.puts("Using User ID: #{id}")
          id
      end
    end
  end

  defp get_header(message, header_name) do
    if message.payload && message.payload.headers do
      header = Enum.find(message.payload.headers, fn h -> h.name == header_name end)
      if header, do: header.value, else: nil
    end
  end

  defp extract_body(payload) do
    cond do
      payload.body && payload.body.data ->
        Base.decode64!(payload.body.data, padding: false)

      payload.parts ->
        # Find text/plain or text/html part
        part =
          Enum.find(payload.parts, fn p ->
            p.mimeType in ["text/plain", "text/html"]
          end)

        if part && part.body && part.body.data do
          Base.decode64!(part.body.data, padding: false)
        end

      true ->
        nil
    end
  end

  defp show_help do
    IO.puts("""

    Gmail Test Commands

    List messages:
      mix test.gmail list                 # List 10 recent messages
      mix test.gmail list --max 20        # List 20 messages

    Search messages:
      mix test.gmail search "from:user@example.com"
      mix test.gmail search "subject:meeting" --max 5

    Send email:
      mix test.gmail send \\
        --to "user@example.com" \\
        --subject "Test Email" \\
        --body "<p>Hello World</p>" \\
        --text "Hello World"

    Get specific message:
      mix test.gmail get <message_id>

    List labels:
      mix test.gmail labels

    """)
  end
end
