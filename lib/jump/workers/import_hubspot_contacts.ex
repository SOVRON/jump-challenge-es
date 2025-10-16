defmodule Jump.Workers.ImportHubspotContacts do
  @moduledoc """
  Oban worker for importing HubSpot contacts into the RAG pipeline.
  """

  use Oban.Worker, queue: :ingest, max_attempts: 3, unique: [period: 300]

  alias Jump.RAG
  alias Jump.HubSpot.Chunker
  require Logger

  @default_limit 100

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"user_id" => user_id}}) do
    Logger.info("Starting HubSpot contact import for user #{user_id}")

    case get_hubspot_client(user_id) do
      {:ok, client} ->
        import_contacts(client, user_id)

      {:error, reason} ->
        Logger.error("Failed to get HubSpot client for user #{user_id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Private functions

  defp get_hubspot_client(user_id) do
    case Jump.Accounts.get_oauth_account(user_id, :hubspot) do
      {:ok, oauth_account} ->
        # Return a client with the access token
        {:ok, oauth_account.access_token}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp import_contacts(access_token, user_id) do
    # Fetch all contacts from HubSpot API
    case fetch_all_contacts(access_token) do
      {:ok, contacts} ->
        Logger.info("Found #{length(contacts)} HubSpot contacts for user #{user_id}")

        # Process each contact
        process_contacts(contacts, user_id)

        :ok

      {:error, reason} ->
        Logger.error("Failed to fetch HubSpot contacts: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp fetch_all_contacts(access_token, after_id \\ nil) do
    url = "https://api.hubapi.com/crm/v3/objects/contacts"

    params = [
      limit: @default_limit,
      properties:
        ~w(firstname lastname email phone company jobtitle lifecyclestage notes createdate lastmodifieddate)
    ]

    params =
      if after_id do
        params ++ [after: after_id]
      else
        params
      end

    headers = [
      {"Authorization", "Bearer #{access_token}"},
      {"Content-Type", "application/json"}
    ]

    case Req.get(url, headers: headers, params: params) do
      {:ok, response} ->
        case response do
          %{status: 200, body: body} ->
            contacts = body["results"] || []
            paging = body["paging"] || %{}

            # Check if there are more pages
            case paging["next"] do
              %{"after" => next_after} ->
                # Recursively fetch next page
                case fetch_all_contacts(access_token, next_after) do
                  {:ok, more_contacts} ->
                    {:ok, contacts ++ more_contacts}

                  error ->
                    error
                end

              _ ->
                {:ok, contacts}
            end

          %{status: status} ->
            Logger.error("HubSpot API error: #{status}")
            {:error, {:api_error, status}}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp process_contacts(contacts, user_id) do
    Enum.each(contacts, fn contact ->
      # Extract contact data
      contact_id = contact["id"]
      properties = contact["properties"] || %{}

      try do
        # Create chunks from contact
        chunks = Chunker.create_contact_chunks(contact_id, properties, user_id)

        if Enum.empty?(chunks) do
          Logger.debug("No chunks created for HubSpot contact #{contact_id}")
        else
          # Store chunks and schedule embeddings
          Enum.each(chunks, fn chunk_attrs ->
            case RAG.create_chunk(chunk_attrs) do
              {:ok, chunk} ->
                # Schedule embedding for this chunk
                schedule_embedding(chunk.id)

                Logger.debug(
                  "Created and scheduled embedding for HubSpot contact chunk #{chunk.id}"
                )

              {:error, reason} ->
                Logger.error("Failed to create HubSpot contact chunk: #{inspect(reason)}")
            end
          end)
        end
      rescue
        error ->
          Logger.error("Error processing HubSpot contact #{contact_id}: #{inspect(error)}")
      end
    end)
  end

  defp schedule_embedding(chunk_id) do
    %{"chunk_id" => chunk_id}
    |> Jump.Workers.EmbedChunk.new(queue: :embed)
    |> Oban.insert()
  end

  @doc """
  Helper function to manually import HubSpot contacts for a user.
  """
  def import_user_contacts(user_id) do
    %{"user_id" => user_id}
    |> __MODULE__.new()
    |> Oban.insert()
  end
end
