defmodule Jump.Workers.EmbedChunk do
  @moduledoc """
  Oban worker for generating embeddings for RAG chunks using OpenAIEx.
  """

  use Oban.Worker, queue: :embed, max_attempts: 3

  alias Jump.RAG
  require Logger

  @embedding_model "text-embedding-3-small"
  @embedding_dimensions 1536

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"chunk_id" => chunk_id}}) do
    Logger.debug("Generating embedding for chunk #{chunk_id}")

    case RAG.get_chunk!(chunk_id) do
      nil ->
        Logger.error("Chunk #{chunk_id} not found")
        {:error, :not_found}

      chunk ->
        generate_and_store_embedding(chunk)
    end
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"text" => text, "chunk_id" => chunk_id}}) do
    # For chunks that might not exist yet
    Logger.debug("Generating embedding for text with chunk_id #{chunk_id}")

    case generate_embedding(text) do
      {:ok, embedding} ->
        Logger.info("Successfully generated embedding for chunk #{chunk_id}")
        {:ok, embedding}

      {:error, reason} ->
        Logger.error("Failed to generate embedding for chunk #{chunk_id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Private functions

  defp generate_and_store_embedding(chunk) do
    # Skip if embedding already exists
    if chunk.embedding do
      Logger.debug("Chunk #{chunk.id} already has embedding, skipping")
      :ok
    else
      case generate_embedding(chunk.text) do
        {:ok, embedding} ->
          case RAG.update_chunk_embedding(chunk.id, embedding) do
            {:ok, _updated_chunk} ->
              Logger.debug("Successfully stored embedding for chunk #{chunk.id}")
              :ok

            {:error, reason} ->
              Logger.error("Failed to store embedding for chunk #{chunk.id}: #{inspect(reason)}")
              {:error, reason}
          end

        {:error, reason} ->
          Logger.error("Failed to generate embedding for chunk #{chunk.id}: #{inspect(reason)}")
          {:error, reason}
      end
    end
  end

  @doc """
  Generate embedding for text using OpenAIEx.
  """
  def generate_embedding(text) do
    # Check if OpenAI API key is configured
    api_key = System.get_env("OPENAI_API_KEY")

    if is_nil(api_key) or api_key == "" do
      Logger.error("OpenAI API key not configured")
      {:error, :missing_api_key}
    else
      # Create OpenAIEx client
      openai = OpenaiEx.new(api_key)

      # Prepare text for embedding (truncate if too long)
      prepared_text = prepare_text_for_embedding(text)

      # Create embedding request
      embedding_req = %{
        model: @embedding_model,
        input: prepared_text
      }

      # Call OpenAIEx embedding API
      case OpenaiEx.Embeddings.create(openai, embedding_req) do
        {:ok, response} ->
          case extract_embedding_from_response(response) do
            {:ok, embedding} ->
              # Validate embedding dimensions
              if validate_embedding(embedding) do
                {:ok, embedding}
              else
                Logger.error("Invalid embedding dimensions received")
                {:error, :invalid_embedding_dimensions}
              end

            {:error, reason} ->
              Logger.error("Failed to extract embedding from response: #{inspect(reason)}")
              {:error, reason}
          end

        {:error, reason} ->
          Logger.error("OpenAIEx embedding API call failed: #{inspect(reason)}")
          {:error, reason}
      end
    end
  end

  defp prepare_text_for_embedding(text) do
    # OpenAI has input token limits for embeddings
    # text-embedding-3-small has a max of 8191 tokens
    # We'll truncate to ~8000 characters as a conservative estimate

    max_length = 8000

    if String.length(text) > max_length do
      Logger.warning(
        "Text too long for embedding, truncating from #{String.length(text)} to #{max_length} characters"
      )

      String.slice(text, 0, max_length)
    else
      text
    end
  end

  defp extract_embedding_from_response(response) do
    case response do
      %{"data" => [embedding_data | _]} ->
        case Map.get(embedding_data, "embedding") do
          nil -> {:error, :no_embedding_in_response}
          embedding -> {:ok, embedding}
        end

      %{"error" => error} ->
        {:error, {:openai_error, error}}

      _ ->
        {:error, :unexpected_response_format}
    end
  end

  defp validate_embedding(embedding) do
    is_list(embedding) and
      length(embedding) == @embedding_dimensions and
      Enum.all?(embedding, fn x -> is_number(x) and x >= -1.0 and x <= 1.0 end)
  end

  # Helper functions for batch processing

  @doc """
  Generate embeddings for multiple chunks in batch using OpenAIEx.
  """
  def generate_embeddings_batch(chunk_texts) do
    api_key = System.get_env("OPENAI_API_KEY")

    if is_nil(api_key) or api_key == "" do
      {:error, :missing_api_key}
    else
      # Create OpenAIEx client
      openai = OpenaiEx.new(api_key)

      # Prepare texts for embedding
      prepared_texts = Enum.map(chunk_texts, &prepare_text_for_embedding/1)

      # Create embedding request for batch
      embedding_req = %{
        model: @embedding_model,
        input: prepared_texts
      }

      # Call OpenAIEx embedding API
      case OpenaiEx.Embeddings.create(openai, embedding_req) do
        {:ok, response} ->
          case extract_embeddings_batch_from_response(response) do
            {:ok, embeddings} ->
              if validate_embeddings_batch(embeddings) do
                {:ok, embeddings}
              else
                {:error, :invalid_embedding_dimensions}
              end

            {:error, reason} ->
              {:error, reason}
          end

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp extract_embeddings_batch_from_response(response) do
    case response do
      %{"data" => embedding_data_list} ->
        embeddings =
          Enum.map(embedding_data_list, fn data ->
            Map.get(data, "embedding")
          end)

        if Enum.all?(embeddings, &is_list/1) do
          {:ok, embeddings}
        else
          {:error, :invalid_embedding_format}
        end

      %{"error" => error} ->
        {:error, {:openai_error, error}}

      _ ->
        {:error, :unexpected_response_format}
    end
  end

  defp validate_embeddings_batch(embeddings) do
    Enum.all?(embeddings, &validate_embedding/1)
  end

  # Helper function to retry failed embeddings
  @doc """
  Schedule retry for failed embedding.
  """
  def schedule_retry(chunk_id, attempt \\ 1) do
    if attempt <= 3 do
      # Exponential backoff
      delay = :timer.seconds(30 * attempt)

      %{"chunk_id" => chunk_id}
      |> __MODULE__.new(schedule_in: delay, max_attempts: 3)
      |> Oban.insert()
    else
      Logger.error("Max retries exceeded for chunk #{chunk_id}")
    end
  end
end
