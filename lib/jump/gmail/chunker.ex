defmodule Jump.Gmail.Chunker do
  @moduledoc """
  Chunks email content for RAG pipeline with configurable token sizes and overlap.
  """

  @default_chunk_size 800
  @default_overlap 125
  @min_chunk_size 700
  @max_chunk_size 900
  @min_overlap 100
  @max_overlap 150

  @doc """
  Chunk email content into smaller pieces with overlap.
  """
  def chunk_content(processed_message, opts \\ []) do
    chunk_size = Keyword.get(opts, :chunk_size, @default_chunk_size)
    overlap = Keyword.get(opts, :overlap, @default_overlap)

    content = processed_message.body_content.content

    if String.length(content) == 0 do
      []
    else
      content
      |> split_into_chunks(chunk_size, overlap)
      |> add_metadata_to_chunks(processed_message)
      |> add_chunk_indices()
    end
  end

  @doc """
  Estimate token count using simple heuristics.
  This is a rough approximation - for production, use a proper tokenizer.
  """
  def estimate_tokens(text) do
    # Rough estimate: ~4 characters per token for English text
    # This is conservative and may underestimate for complex text
    text
    |> String.replace(~r/\s+/, " ")
    |> String.length()
    |> div(4)
  end

  @doc """
  Check if a chunk is within acceptable token range.
  """
  def chunk_size_valid?(chunk_text, opts \\ []) do
    min_size = Keyword.get(opts, :min_size, @min_chunk_size)
    max_size = Keyword.get(opts, :max_size, @max_chunk_size)

    token_count = estimate_tokens(chunk_text)
    token_count >= min_size and token_count <= max_size
  end

  @doc """
  Adjust chunk to fit within token limits.
  """
  def adjust_chunk_size(chunk_text, opts \\ []) do
    max_size = Keyword.get(opts, :max_size, @max_chunk_size)
    min_size = Keyword.get(opts, :min_size, @min_chunk_size)

    current_tokens = estimate_tokens(chunk_text)

    cond do
      current_tokens <= max_size and current_tokens >= min_size ->
        {:ok, chunk_text}

      current_tokens > max_size ->
        # Try to find a good breaking point
        case find_break_point(chunk_text, max_size) do
          {:ok, trimmed_chunk} ->
            {:ok, trimmed_chunk}

          :no_break_point ->
            # Force truncate if no good break point
            truncated = String.slice(chunk_text, 0, max_size * 4)
            {:ok, truncated}
        end

      current_tokens < min_size ->
        # Chunk is too small, may need to merge with adjacent chunks
        {:too_small, chunk_text}
    end
  end

  @doc """
  Create chunks with proper metadata for RAG storage.
  """
  def create_rag_chunks(processed_message, opts \\ []) do
    chunks = chunk_content(processed_message, opts)

    Enum.map(chunks, fn chunk ->
      %{
        user_id: Map.get(opts, :user_id),
        source: "gmail",
        source_id: processed_message.message_id,
        text: chunk.text,
        meta: chunk.meta,
        person_email: get_primary_sender_email(processed_message),
        person_name: get_primary_sender_name(processed_message)
      }
    end)
  end

  # Private helper functions

  defp split_into_chunks(text, chunk_size, overlap) do
    words = String.split(text, ~r/\s+/)
    split_into_chunks_recursive(words, chunk_size * 4, overlap * 4, [], 0)
  end

  defp split_into_chunks_recursive([], _chunk_chars, _overlap_chars, chunks, _position),
    do: Enum.reverse(chunks)

  defp split_into_chunks_recursive(words, chunk_chars, overlap_chars, chunks, position) do
    # Take words until we exceed chunk size
    {chunk_words, remaining_words} = take_words_up_to_size(words, chunk_chars)

    chunk_text = Enum.join(chunk_words, " ")

    # Move position by actual chunk size (not chunk_chars target)
    actual_chunk_chars = String.length(chunk_text)
    new_position = position + actual_chunk_chars

    new_chunks = [%{text: chunk_text, position: position} | chunks]

    # Calculate overlap for next chunk
    overlap_words =
      String.split(
        String.slice(chunk_text, max(0, actual_chunk_chars - overlap_chars)..-1//1),
        ~r/\s+/
      )

    # Continue with remaining words plus overlap
    next_words = overlap_words ++ remaining_words

    split_into_chunks_recursive(next_words, chunk_chars, overlap_chars, new_chunks, new_position)
  end

  defp take_words_up_to_size(words, max_chars) do
    take_words_up_to_size(words, max_chars, [], 0)
  end

  defp take_words_up_to_size([], _max_chars, acc_words, _current_chars) do
    {Enum.reverse(acc_words), []}
  end

  defp take_words_up_to_size([word | rest], max_chars, acc_words, current_chars) do
    # +1 for space
    word_chars = String.length(word) + 1

    if current_chars + word_chars > max_chars and acc_words != [] do
      {Enum.reverse(acc_words), [word | rest]}
    else
      take_words_up_to_size(rest, max_chars, [word | acc_words], current_chars + word_chars)
    end
  end

  defp add_metadata_to_chunks(chunks, processed_message) do
    Enum.map(chunks, fn chunk ->
      meta = %{
        message_id: processed_message.message_id,
        thread_id: processed_message.thread_id,
        subject: processed_message.participants.subject,
        from: processed_message.participants.from,
        date: processed_message.participants.date,
        position: chunk.position,
        total_chunks: length(chunks),
        # Will be added by add_chunk_indices
        chunk_index: nil,
        content_type: processed_message.body_content.content_type,
        snippet: String.slice(processed_message.snippet, 0, 200),
        is_reply: Jump.Gmail.Processor.is_reply?(processed_message),
        participants: Jump.Gmail.Processor.extract_all_addresses(processed_message)
      }

      %{chunk | meta: meta}
    end)
  end

  defp add_chunk_indices(chunks) do
    chunks
    |> Enum.with_index()
    |> Enum.map(fn {chunk, index} ->
      updated_meta = Map.put(chunk.meta, :chunk_index, index)
      %{chunk | meta: updated_meta}
    end)
  end

  defp find_break_point(text, max_tokens) do
    target_chars = max_tokens * 4

    # Try to break at sentence boundaries first
    case Regex.compile(~r/(?<=[.!?])\s+/) do
      {:ok, regex} ->
        case find_last_match_before_position(text, regex, target_chars) do
          {:ok, position} ->
            {:ok, String.slice(text, 0, position)}

          :no_match ->
            # Try paragraph boundaries
            find_paragraph_break(text, target_chars)
        end
    end
  end

  defp find_last_match_before_position(text, regex, max_position) do
    case Regex.run(regex, text, return: :index) do
      nil ->
        :no_match

      matches ->
        case Enum.find(matches, fn {start, _len} -> start < max_position end) do
          nil -> :no_match
          {position, _length} -> {:ok, position}
        end
    end
  end

  defp find_paragraph_break(text, max_position) do
    case Regex.compile(~r/\n{2,}/) do
      {:ok, regex} ->
        case find_last_match_before_position(text, regex, max_position) do
          {:ok, position} ->
            {:ok, String.slice(text, 0, position)}

          :no_match ->
            # Try single line breaks
            case Regex.compile(~r/\n/) do
              {:ok, line_regex} ->
                case find_last_match_before_position(text, line_regex, max_position) do
                  {:ok, position} ->
                    {:ok, String.slice(text, 0, position)}

                  :no_match ->
                    :no_break_point
                end
            end
        end
    end
  end

  defp get_primary_sender_email(processed_message) do
    case processed_message.participants.from do
      nil -> nil
      %{email: email} -> email
      _ -> nil
    end
  end

  defp get_primary_sender_name(processed_message) do
    case processed_message.participants.from do
      nil -> nil
      %{name: name} when name != "" -> name
      %{email: email} -> email
      _ -> nil
    end
  end
end
