defmodule Jump.Gmail.Composer do
  @moduledoc """
  Composes RFC 2822 email messages using Swoosh/Mail for Gmail API.
  """

  alias Swoosh.Email
  require Logger

  @doc """
  Build a complete email message.
  """
  def build_email(opts) do
    from = Keyword.get(opts, :from)
    to = Keyword.get(opts, :to, [])
    cc = Keyword.get(opts, :cc, [])
    bcc = Keyword.get(opts, :bcc, [])
    subject = Keyword.get(opts, :subject, "")
    html_body = Keyword.get(opts, :html_body)
    text_body = Keyword.get(opts, :text_body)
    reply_to_message_id = Keyword.get(opts, :reply_to_message_id)
    references = Keyword.get(opts, :references, [])

    # Build Swoosh email
    email =
      Email.new()
      |> Email.from(from)
      |> Email.to(to)
      |> Email.cc(cc)
      |> Email.bcc(bcc)
      |> Email.subject(subject)

    # Add body content
    email =
      cond do
        html_body && text_body ->
          email
          |> Email.html_body(html_body)
          |> Email.text_body(text_body)

        html_body ->
          email
          |> Email.html_body(html_body)
          |> Email.text_body(html_to_text(html_body))

        text_body ->
          Email.text_body(email, text_body)

        true ->
          email
      end

    # Add threading headers if replying
    if reply_to_message_id do
      add_threading_headers(email, reply_to_message_id, references)
    else
      email
    end
  end

  @doc """
  Convert Swoosh email to RFC 2822 format for Gmail API.
  """
  def to_rfc2822(%Swoosh.Email{} = email) do
    # Use Swoosh's email renderer
    Swoosh.Email.Renderer.render(email)
  end

  @doc """
  Convert email to Base64url encoded string for Gmail API.
  """
  def to_base64url(%Swoosh.Email{} = email) do
    email
    |> to_rfc2822()
    |> Base.encode64(padding: false)
  end

  @doc """
  Create a reply email.
  """
  def build_reply(original_message, opts \\ []) do
    # Extract threading info from original message
    original_headers = extract_message_headers(original_message)
    reply_to = get_reply_to_address(original_headers)
    references = get_references(original_headers)

    # Build reply options
    reply_opts =
      [
        to: [reply_to],
        subject: build_reply_subject(original_headers[:subject]),
        reply_to_message_id: original_headers[:message_id],
        references: references
      ]
      |> Keyword.merge(opts)

    # Remove from if it's not explicitly set (Gmail will use authenticated user)
    reply_opts = Keyword.delete(reply_opts, :from)

    build_email(reply_opts)
  end

  @doc """
  Create a forward email.
  """
  def build_forward(original_message, opts \\ []) do
    original_headers = extract_message_headers(original_message)
    original_body = extract_message_body(original_message)

    # Build forward options
    forward_opts =
      [
        subject: build_forward_subject(original_headers[:subject])
      ]
      |> Keyword.merge(opts)

    # Add forwarded content
    html_body = Keyword.get(opts, :html_body, "")
    text_body = Keyword.get(opts, :text_body, "")

    forward_html = build_forward_content_html(html_body, original_message)
    forward_text = build_forward_content_text(text_body, original_message)

    forward_opts =
      forward_opts
      |> Keyword.put(:html_body, forward_html)
      |> Keyword.put(:text_body, forward_text)

    build_email(forward_opts)
  end

  @doc """
  Create a new email thread.
  """
  def build_new_thread(opts) do
    # Ensure new thread has message ID
    build_email(opts)
  end

  @doc """
  Validate email addresses.
  """
  def validate_addresses(addresses) when is_list(addresses) do
    Enum.all?(addresses, &validate_address/1)
  end

  def validate_address(address) when is_binary(address) do
    # Simple email validation regex
    email_regex = ~r/^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$/
    Regex.match?(email_regex, address)
  end

  def validate_address(_), do: false

  @doc """
  Generate Message-ID for new emails.
  """
  def generate_message_id(domain \\ nil) do
    domain = domain || get_default_domain()
    timestamp = System.system_time(:microsecond)
    random = :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
    "<#{timestamp}.#{random}@#{domain}>"
  end

  # Private helper functions

  defp add_threading_headers(email, reply_to_message_id, references) do
    message_id = generate_message_id()

    email
    |> Email.header("In-Reply-To", reply_to_message_id)
    |> Email.header("References", build_references_header(references ++ [reply_to_message_id]))
    |> Email.header("Message-ID", message_id)
  end

  defp build_references_header(references) do
    references
    |> Enum.reverse()
    |> Enum.join(" ")
  end

  defp extract_message_headers(message) do
    # This would depend on the message format
    # For now, return empty map - in real implementation, extract from Gmail message
    %{
      message_id: "",
      subject: "",
      from: "",
      to: [],
      cc: [],
      references: []
    }
  end

  defp extract_message_body(message) do
    # Extract body content from message
    # This would depend on the message format
    %{
      html: "",
      text: "",
      date: nil
    }
  end

  defp get_reply_to_address(headers) do
    # Determine reply-to address
    # Priority: Reply-To header, From header, first To recipient
    reply_to = headers[:reply_to] || headers[:from]

    case reply_to do
      %{email: email} -> email
      email when is_binary(email) -> email
      _ -> ""
    end
  end

  defp get_references(headers) do
    # Get existing references for threading
    headers[:references] || []
  end

  defp build_reply_subject(original_subject) do
    if String.starts_with?(original_subject || "", "Re: ") do
      original_subject
    else
      "Re: " <> (original_subject || "")
    end
  end

  defp build_forward_subject(original_subject) do
    if String.starts_with?(original_subject || "", "Fwd: ") do
      original_subject
    else
      "Fwd: " <> (original_subject || "")
    end
  end

  defp build_forward_content_html(user_content, original_message) do
    original_headers = extract_message_headers(original_message)
    original_body = extract_message_body(original_message)

    forward_header = """
    <br><br>
    <div style="border-left: 2px solid #ccc; padding-left: 10px; margin-left: 0;">
    <p>---------- Forwarded message ---------<br>
    From: #{format_address(original_headers[:from])}<br>
    Date: #{format_date(original_body[:date])}<br>
    Subject: #{original_headers[:subject]}<br>
    To: #{format_addresses(original_headers[:to])}</p>
    <br>
    #{original_body[:html]}
    </div>
    """

    user_content <> forward_header
  end

  defp build_forward_content_text(user_content, original_message) do
    original_headers = extract_message_headers(original_message)
    original_body = extract_message_body(original_message)

    forward_header = """

    ---------- Forwarded message ---------
    From: #{format_address(original_headers[:from])}
    Date: #{format_date(original_body[:date])}
    Subject: #{original_headers[:subject]}
    To: #{format_addresses(original_headers[:to])}

    #{original_body[:text]}
    """

    user_content <> forward_header
  end

  defp format_address(nil), do: ""

  defp format_address(%{name: name, email: email}) when name != "" do
    "#{name} <#{email}>"
  end

  defp format_address(%{email: email}), do: email
  defp format_address(address), do: to_string(address)

  defp format_addresses([]), do: ""

  defp format_addresses(addresses) do
    addresses
    |> Enum.map(&format_address/1)
    |> Enum.join(", ")
  end

  defp format_date(nil), do: ""

  defp format_date(datetime) do
    Timex.format!(datetime, "{RFC1123}")
  end

  defp html_to_text(html) do
    html
    |> Floki.parse_document!()
    |> Floki.text()
    |> String.trim()
  end

  defp get_default_domain do
    # Get domain from environment or use a default
    System.get_env("MAIL_DOMAIN") || "localhost"
  end

  # Template helpers

  @doc """
  Create email with signature.
  """
  def with_signature(email, signature \\ nil) do
    signature = signature || get_default_signature()

    if signature && signature != "" do
      html_body = email.html_body || ""
      text_body = email.text_body || ""

      email
      |> Email.html_body(html_body <> "<br><br>#{signature}")
      |> Email.text_body(text_body <> "\n\n#{signature}")
    else
      email
    end
  end

  defp get_default_signature do
    # Get signature from environment or user settings
    System.get_env("EMAIL_SIGNATURE") || ""
  end

  @doc """
  Add tracking pixel to email.
  """
  def with_tracking_pixel(email, tracking_url) do
    html_body = email.html_body || ""

    tracking_pixel = """
    <img src="#{tracking_url}" width="1" height="1" border="0" style="display:none;">
    """

    Email.html_body(email, html_body <> tracking_pixel)
  end

  @doc """
  Add unsubscribe link to email.
  """
  def with_unsubscribe_link(email, unsubscribe_url) do
    unsubscribe_text = """

    ---
    To unsubscribe from these emails, click here: #{unsubscribe_url}
    """

    text_body = email.text_body || ""
    Email.text_body(email, text_body <> unsubscribe_text)
  end
end
