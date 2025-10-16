defmodule Jump.CRM.Hubspot.Client do
  @moduledoc """
  HubSpot CRM API client using Req library.
  """

  alias Jump.Accounts
  require Logger

  @base_url "https://api.hubapi.com/crm/v3"

  @doc """
  Get a client configured with HubSpot OAuth token for a user.
  """
  def get_client(user_id) do
    case Accounts.get_oauth_account(user_id, :hubspot) do
      {:ok, oauth_account} ->
        {:ok, build_client(oauth_account.access_token)}

      {:error, :not_found} ->
        {:error, :hubspot_not_connected}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Build a Req client with HubSpot authentication.
  """
  def build_client(access_token) do
    Req.new(
      base_url: @base_url,
      headers: [
        {"Authorization", "Bearer #{access_token}"},
        {"Content-Type", "application/json"}
      ],
      retry: :transient,
      max_retries: 3
    )
  end

  @doc """
  Get a contact by email address.
  """
  def get_contact_by_email(client, email) do
    Req.post(client,
      url: "#{client.base_url}/objects/contacts/search",
      json: %{
        filterGroups: [
          %{
            filters: [
              %{
                propertyName: "email",
                operator: "EQ",
                value: email
              }
            ]
          }
        ]
      }
    )
  end

  @doc """
  Search contacts by various criteria.
  """
  def search_contacts(client, search_term, opts \\ []) do
    limit = Keyword.get(opts, :limit, 10)
    after_value = Keyword.get(opts, :after)

    search_body = %{
      filterGroups: [
        %{
          filters: [
            %{
              propertyName: "firstname",
              operator: "CONTAINS_TOKEN",
              value: search_term
            },
            %{
              propertyName: "lastname",
              operator: "CONTAINS_TOKEN",
              value: search_term
            },
            %{
              propertyName: "email",
              operator: "CONTAINS_TOKEN",
              value: search_term
            }
          ]
        }
      ],
      limit: limit,
      sorts: [
        %{
          propertyName: "hs_createdate",
          direction: "DESCENDING"
        }
      ]
    }

    search_body = if after_value, do: Map.put(search_body, :after, after_value), else: search_body

    Req.post(client, url: "#{client.base_url}/objects/contacts/search", json: search_body)
  end

  @doc """
  Create a new contact.
  """
  def create_contact(client, email, name \\ "", properties \\ %{}) do
    properties =
      Map.merge(properties, %{
        "email" => email,
        "firstname" => extract_first_name(name),
        "lastname" => extract_last_name(name)
      })

    Req.post(client,
      url: "#{client.base_url}/objects/contacts",
      json: %{
        properties: properties
      }
    )
  end

  @doc """
  Create a note for a contact.
  """
  def create_note(client, contact_id, text, opts \\ []) do
    timestamp = Keyword.get(opts, :timestamp, DateTime.utc_now())

    properties = %{
      # HubSpot uses milliseconds
      "hs_timestamp" => DateTime.to_unix(timestamp) * 1000,
      "hs_note_body" => text,
      "hs_object_source" => "INTEGRATION",
      "hs_object_source_id" => "NOTE"
    }

    Req.post(client,
      url: "#{client.base_url}/objects/notes",
      json: %{
        properties: properties,
        associations: [
          %{
            to: %{
              id: contact_id,
              type: "contact"
            },
            types: [
              %{
                associationCategory: "HUBSPOT_DEFINED",
                # Note to Contact association
                associationTypeId: 0
              }
            ]
          }
        ]
      }
    )
  end

  @doc """
  List recent contacts.
  """
  def list_recent_contacts(client, opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)
    after_value = Keyword.get(opts, :after)

    search_body = %{
      filterGroups: [
        %{
          filters: [
            %{
              propertyName: "createdate",
              operator: "GTE",
              value: DateTime.to_unix(DateTime.add(DateTime.utc_now(), -30, :day)) * 1000
            }
          ]
        }
      ],
      limit: limit,
      sorts: [
        %{
          propertyName: "createdate",
          direction: "DESCENDING"
        }
      ]
    }

    search_body = if after_value, do: Map.put(search_body, :after, after_value), else: search_body

    Req.post(client, url: "#{client.base_url}/objects/contacts/search", json: search_body)
  end

  # Helper functions

  defp extract_first_name("") do
    ""
  end

  defp extract_first_name(name) do
    name
    |> String.split(" ", parts: 2)
    |> Enum.at(0, "")
    |> String.trim()
  end

  defp extract_last_name("") do
    ""
  end

  defp extract_last_name(name) do
    name
    |> String.split(" ", parts: 2)
    |> Enum.at(1, "")
    |> String.trim()
  end
end
