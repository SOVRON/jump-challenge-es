defmodule Jump.Gmail.Processor do
  @moduledoc """
  Processes Gmail messages, extracts content, headers, and participant information.
  """

  require Logger

  @doc """
  Extract headers from a Gmail message.
  """
  def extract_headers(%{payload: %{headers: headers}}) do
    Enum.reduce(headers, %{}, fn header, acc ->
      Map.put(acc, String.downcase(header.name), header.value)
    end)
  end

  def extract_headers(_message), do: %{}

  @doc """
  Extract participant information from headers.
  """
  def extract_participants(headers) do
    %{
      from: parse_address(headers["from"]),
      to: parse_addresses(headers["to"]),
      cc: parse_addresses(headers["cc"]),
      bcc: parse_addresses(headers["bcc"]),
      date: parse_date(headers["date"]),
      subject: headers["subject"] || "",
      message_id: headers["message-id"] || "",
      references: parse_references(headers["references"]),
      in_reply_to: parse_address(headers["in-reply-to"]),
      thread_id: extract_thread_id(headers)
    }
  end

  @doc """
  Extract email body content (HTML or plain text).
  """
  def extract_body_content(%{payload: payload}) do
    case find_best_body_part(payload) do
      {content_type, content} ->
        cleaned_content = clean_content(content, content_type)

        %{
          content_type: content_type,
          content: cleaned_content,
          raw_content: content
        }

      nil ->
        %{
          content_type: "plain",
          content: "",
          raw_content: ""
        }
    end
  end

  def extract_body_content(_message), do: %{content_type: "plain", content: "", raw_content: ""}

  @doc """
  Process a complete Gmail message and extract all relevant information.
  """
  def process_message(message) do
    headers = extract_headers(message)
    participants = extract_participants(headers)
    body_content = extract_body_content(message)

    %{
      message_id: get_message_id(message),
      thread_id: get_thread_id(message),
      history_id: get_history_id(message),
      participants: participants,
      body_content: body_content,
      snippet: Map.get(message, :snippet, ""),
      internal_date: get_internal_date(message),
      label_ids: get_label_ids(message),
      size_estimate: Map.get(message, :sizeEstimate, 0)
    }
  end

  @doc """
  Extract all email addresses from message as participants.
  """
  def extract_all_addresses(processed_message) do
    participants = processed_message.participants

    addresses =
      []
      |> add_address(participants.from)
      |> add_addresses(participants.to)
      |> add_addresses(participants.cc)
      |> add_addresses(participants.bcc)

    Enum.uniq(addresses)
  end

  @doc """
  Get primary sender information.
  """
  def get_primary_sender(processed_message) do
    processed_message.participants.from
  end

  @doc """
  Get all recipients (to, cc, bcc).
  """
  def get_all_recipients(processed_message) do
    participants = processed_message.participants

    (participants.to ++ participants.cc ++ participants.bcc)
    |> Enum.uniq()
  end

  @doc """
  Determine if message is a reply based on headers.
  """
  def is_reply?(processed_message) do
    participants = processed_message.participants
    references = participants.references
    in_reply_to = participants.in_reply_to

    not (references == [] and is_nil(in_reply_to))
  end

  @doc """
  Extract thread conversation chain.
  """
  def extract_thread_chain(processed_message) do
    references = processed_message.participants.references
    in_reply_to = processed_message.participants.in_reply_to

    chain =
      []
      |> add_if_not_nil(in_reply_to)
      |> concat_uniq(references)

    chain
  end

  # Private helper functions

  defp find_best_body_part(payload) do
    # Prefer HTML content, fallback to plain text
    case find_part_by_mime_type(payload, "text/html") do
      {content_type, content} ->
        {content_type, content}

      nil ->
        case find_part_by_mime_type(payload, "text/plain") do
          {content_type, content} -> {content_type, content}
          nil -> nil
        end
    end
  end

  defp find_part_by_mime_type(%{mimeType: mime_type, body: body} = payload, target_type) do
    if mime_type == target_type do
      {mime_type, decode_body(body)}
    else
      # Check nested parts
      case payload.parts do
        nil ->
          nil

        parts ->
          Enum.find_value(parts, fn part ->
            find_part_by_mime_type(part, target_type)
          end)
      end
    end
  end

  defp find_part_by_mime_type(_payload, _target_type), do: nil

  defp decode_body(%{data: data}), do: Base.url_decode64!(data, padding: false)
  defp decode_body(_), do: ""

  defp clean_content(content, "text/html") do
    content
    |> Floki.parse_document!()
    |> Floki.find("body")
    |> Floki.text()
    |> clean_text_content()
  end

  defp clean_content(content, "text/plain") do
    content
    |> clean_text_content()
  end

  defp clean_content(content, _), do: clean_text_content(content)

  defp clean_text_content(text) do
    text
    |> String.replace(~r/On .+ wrote:/s, "\n--- Previous Message ---\n")
    |> String.replace(~r/>+ .+/, "")
    |> String.replace(
      ~r/-----BEGIN PGP MESSAGE-----.+-----END PGP MESSAGE-----/s,
      "[ENCRYPTED CONTENT]"
    )
    |> String.replace(
      ~r/-----BEGIN PGP SIGNATURE-----.+-----END PGP SIGNATURE-----/s,
      "[SIGNATURE]"
    )
    |> String.replace(~r/\n{3,}/, "\n\n")
    |> String.trim()
  end

  defp parse_address(nil), do: nil

  defp parse_address(address_string) do
    case Regex.run(~r/^(?:"?([^"]*)"?\s)?(?:<?(.+@[^>]+)>?)$/, address_string) do
      [_, name, email] ->
        %{
          name: String.trim(name || ""),
          email: String.trim(email),
          full: address_string
        }

      [_, email] ->
        %{
          name: "",
          email: String.trim(email),
          full: address_string
        }

      _ ->
        %{
          name: "",
          email: String.trim(address_string),
          full: address_string
        }
    end
  end

  defp parse_addresses(nil), do: []

  defp parse_addresses(addresses_string) do
    addresses_string
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.map(&parse_address/1)
    |> Enum.filter(& &1)
  end

  defp parse_date(nil), do: nil

  defp parse_date(date_string) do
    case Timex.parse(date_string, "{RFC1123}") do
      {:ok, datetime} ->
        datetime

      {:error, _} ->
        case Timex.parse(date_string, "{RFC822}") do
          {:ok, datetime} -> datetime
          {:error, _} -> nil
        end
    end
  end

  defp parse_references(nil), do: []

  defp parse_references(references_string) do
    references_string
    |> String.split(["<", ">", " "], trim: true)
    |> Enum.filter(&String.contains?(&1, "@"))
  end

  defp extract_thread_id(headers) do
    # Gmail uses Message-ID for threading, but we can also use References
    headers["message-id"] ||
      case headers["references"] do
        nil -> nil
        refs -> refs |> String.split() |> List.last()
      end
  end

  defp get_message_id(%{id: id}), do: id
  defp get_message_id(_), do: ""

  defp get_thread_id(%{threadId: thread_id}), do: thread_id
  defp get_thread_id(_), do: ""

  defp get_history_id(%{historyId: history_id}), do: history_id
  defp get_history_id(_), do: ""

  defp get_internal_date(%{internalDate: timestamp}) when is_binary(timestamp) do
    {timestamp_int, ""} = Integer.parse(timestamp)
    DateTime.from_unix!(timestamp_int, :millisecond)
  end

  defp get_internal_date(_), do: DateTime.utc_now()

  defp get_label_ids(%{labelIds: label_ids}) when is_list(label_ids), do: label_ids
  defp get_label_ids(_), do: []

  defp add_address(addresses, nil), do: addresses
  defp add_address(addresses, address), do: [address | addresses]

  defp add_addresses(addresses, nil), do: addresses
  defp add_addresses(addresses, new_addresses), do: new_addresses ++ addresses

  defp add_if_not_nil(list, nil), do: list
  defp add_if_not_nil(list, item), do: [item | list]

  defp concat_uniq(list1, list2), do: list1 ++ (list2 -- list1)
end
