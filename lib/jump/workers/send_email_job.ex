defmodule Jump.Workers.SendEmailJob do
  @moduledoc """
  Oban worker for sending emails via Gmail API.
  """

  use Oban.Worker, queue: :outbound, max_attempts: 3

  alias Jump.Gmail.Client
  alias Jump.Gmail.Composer
  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"user_id" => user_id, "email_params" => email_params}}) do
    Logger.info("Sending email for user #{user_id}")

    case Client.get_conn(user_id) do
      {:ok, conn} ->
        send_email(conn, user_id, email_params)

      {:error, reason} ->
        Logger.error("Failed to get Gmail connection for user #{user_id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{
          "user_id" => user_id,
          "reply_to" => reply_to_message_id,
          "email_params" => email_params
        }
      }) do
    Logger.info("Sending reply email for user #{user_id} to message #{reply_to_message_id}")

    case Client.get_conn(user_id) do
      {:ok, conn} ->
        send_reply_email(conn, user_id, reply_to_message_id, email_params)

      {:error, reason} ->
        Logger.error("Failed to get Gmail connection for user #{user_id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Private functions

  defp send_email(conn, user_id, email_params) do
    try do
      # Build email
      email = build_email_from_params(email_params)

      # Validate email addresses
      unless validate_email_addresses(email) do
        Logger.error("Invalid email addresses in email parameters")
        {:error, :invalid_addresses}
      end

      # Convert to Gmail format
      raw_message = Composer.to_base64url(email)

      # Add options
      opts =
        []
        |> Keyword.put(:thread_id, email_params["thread_id"])

      # Send via Gmail API
      case Client.send_message(conn, raw_message, opts) do
        {:ok, sent_message} ->
          Logger.info(
            "Successfully sent email for user #{user_id}, message ID: #{sent_message.id}"
          )

          # Record sent message
          record_sent_email(user_id, sent_message.id, email_params)

          {:ok, %{message_id: sent_message.id, thread_id: sent_message.threadId}}

        {:error, reason} ->
          Logger.error("Failed to send email via Gmail API: #{inspect(reason)}")
          {:error, reason}
      end
    rescue
      error ->
        Logger.error("Error sending email: #{inspect(error)}")
        {:error, error}
    end
  end

  defp send_reply_email(conn, user_id, reply_to_message_id, email_params) do
    try do
      # Get original message for threading
      case Client.get_message(conn, reply_to_message_id, format: "metadata", headers: true) do
        {:ok, original_message} ->
          # Build reply email
          reply_opts =
            [
              reply_to_message_id: reply_to_message_id,
              thread_id: original_message.threadId
            ]
            |> Keyword.merge(Enum.into(email_params, %{}))

          reply_email = Composer.build_reply(original_message, reply_opts)

          # Validate email addresses
          unless validate_email_addresses(reply_email) do
            Logger.error("Invalid email addresses in reply parameters")
            {:error, :invalid_addresses}
          end

          # Convert to Gmail format
          raw_message = Composer.to_base64url(reply_email)

          # Send via Gmail API (thread_id automatically used)
          case Client.send_message(conn, raw_message, thread_id: original_message.threadId) do
            {:ok, sent_message} ->
              Logger.info(
                "Successfully sent reply email for user #{user_id}, message ID: #{sent_message.id}"
              )

              # Record sent message
              record_sent_email(user_id, sent_message.id, email_params)

              {:ok, %{message_id: sent_message.id, thread_id: sent_message.threadId}}

            {:error, reason} ->
              Logger.error("Failed to send reply email via Gmail API: #{inspect(reason)}")
              {:error, reason}
          end

        {:error, reason} ->
          Logger.error("Failed to get original message for reply: #{inspect(reason)}")
          {:error, reason}
      end
    rescue
      error ->
        Logger.error("Error sending reply email: #{inspect(error)}")
        {:error, error}
    end
  end

  defp build_email_from_params(email_params) do
    opts =
      [
        from: email_params["from"],
        to: email_params["to"],
        cc: email_params["cc"],
        bcc: email_params["bcc"],
        subject: email_params["subject"],
        html_body: email_params["html_body"],
        text_body: email_params["text_body"]
      ]
      |> Enum.filter(fn {_key, value} -> value != nil end)

    Composer.build_email(opts)
  end

  defp validate_email_addresses(email) do
    # Validate all recipient addresses
    to_addresses = Email.get_to(email) || []
    cc_addresses = Email.get_cc(email) || []
    bcc_addresses = Email.get_bcc(email) || []

    all_addresses = to_addresses ++ cc_addresses ++ bcc_addresses

    all_addresses
    |> Enum.map(fn address ->
      case address do
        %{email: email} -> email
        email when is_binary(email) -> email
        _ -> ""
      end
    end)
    |> Composer.validate_addresses()
  end

  defp record_sent_email(user_id, message_id, email_params) do
    # Record the sent email for future reference
    # This could be stored in a separate sent_emails table or logs
    Logger.info("Recording sent email #{message_id} for user #{user_id}")

    # Store in RAG system for future reference
    sent_email_content = %{
      user_id: user_id,
      source: "gmail_sent",
      source_id: message_id,
      text: build_sent_email_content(email_params),
      meta: %{
        type: "sent_email",
        subject: email_params["subject"],
        to: email_params["to"],
        cc: email_params["cc"],
        sent_at: DateTime.utc_now()
      },
      # Sent emails don't have a single person
      person_email: nil,
      person_name: nil
    }

    # Don't embed sent emails for now to save costs
    # In the future, this could be configurable
    Logger.debug("Skipping embedding for sent email #{message_id}")
  end

  defp build_sent_email_content(email_params) do
    content = "Subject: #{email_params["subject"]}\n"
    content = content <> "To: #{format_addresses(email_params["to"])}\n"

    if email_params["cc"] && email_params["cc"] != [] do
      content = content <> "Cc: #{format_addresses(email_params["cc"])}\n"
    end

    content = content <> "\n"

    # Add body content
    body = email_params["text_body"] || html_to_text(email_params["html_body"] || "")
    content = content <> body

    content
  end

  defp format_addresses(nil), do: ""
  defp format_addresses([]), do: ""

  defp format_addresses(addresses) when is_list(addresses) do
    addresses
    |> Enum.map(fn address ->
      case address do
        %{name: name, email: email} when name != "" -> "#{name} <#{email}>"
        %{email: email} -> email
        email when is_binary(email) -> email
        _ -> ""
      end
    end)
    |> Enum.filter(&(&1 != ""))
    |> Enum.join(", ")
  end

  defp html_to_text(html) do
    html
    |> Floki.parse_document()
    |> case do
      {:ok, document} -> Floki.text(document)
      _ -> html
    end
    |> String.trim()
  end

  # Helper functions for creating email jobs

  @doc """
  Queue a new email to be sent.
  """
  def send_email_async(user_id, to, subject, body, opts \\ []) do
    email_params = %{
      "to" => to,
      "subject" => subject,
      "text_body" => body,
      "html_body" => Keyword.get(opts, :html_body),
      "cc" => Keyword.get(opts, :cc, []),
      "bcc" => Keyword.get(opts, :bcc, []),
      "thread_id" => Keyword.get(opts, :thread_id)
    }

    %{"user_id" => user_id, "email_params" => email_params}
    |> __MODULE__.new()
    |> Oban.insert()
  end

  @doc """
  Queue a reply email to be sent.
  """
  def reply_to_email_async(user_id, reply_to_message_id, to, subject, body, opts \\ []) do
    email_params = %{
      "to" => to,
      "subject" => subject,
      "text_body" => body,
      "html_body" => Keyword.get(opts, :html_body),
      "cc" => Keyword.get(opts, :cc, []),
      "bcc" => Keyword.get(opts, :bcc, [])
    }

    %{"user_id" => user_id, "reply_to" => reply_to_message_id, "email_params" => email_params}
    |> __MODULE__.new()
    |> Oban.insert()
  end

  @doc """
  Send email with HTML content.
  """
  def send_html_email_async(user_id, to, subject, html_body, opts \\ []) do
    text_body = Keyword.get(opts, :text_body, html_to_text(html_body))

    send_email_async(user_id, to, subject, text_body, [html_body: html_body] ++ opts)
  end

  @doc """
  Schedule email to be sent at a specific time.
  """
  def schedule_email(user_id, to, subject, body, scheduled_at, opts \\ []) do
    email_params = %{
      "to" => to,
      "subject" => subject,
      "text_body" => body,
      "html_body" => Keyword.get(opts, :html_body),
      "cc" => Keyword.get(opts, :cc, []),
      "bcc" => Keyword.get(opts, :bcc, []),
      "thread_id" => Keyword.get(opts, :thread_id)
    }

    %{"user_id" => user_id, "email_params" => email_params}
    |> __MODULE__.new(scheduled_at: scheduled_at)
    |> Oban.insert()
  end
end
