defmodule Mix.Tasks.Test.Hubspot do
  @moduledoc """
  Test HubSpot API functions.

  Usage:
    mix test.hubspot list                                  # List contacts
    mix test.hubspot find "user@example.com"               # Find contact by email
    mix test.hubspot create "user@example.com" "John Doe"  # Create contact
    mix test.hubspot note <contact_id> "Meeting notes..."  # Add note to contact
    mix test.hubspot get <contact_id>                      # Get contact details
  """

  use Mix.Task
  require Logger

  alias Jump.{Accounts, Repo}
  import Ecto.Query

  @shortdoc "Test HubSpot API functions"

  def run(args) do
    # Ensure the application and all dependencies are started
    Application.ensure_all_started(:jump)

    case args do
      ["list" | opts] -> list_contacts(opts)
      ["find", email] -> find_contact(email)
      ["create", email, name | opts] -> create_contact(email, name, opts)
      ["note", contact_id, text] -> add_note(contact_id, text)
      ["get", contact_id] -> get_contact(contact_id)
      ["import"] -> import_contacts()
      _ -> show_help()
    end
  end

  defp list_contacts(opts) do
    user_id = get_user_id_from_opts(opts)

    limit =
      if Enum.member?(opts, "--limit") do
        limit_idx = Enum.find_index(opts, &(&1 == "--limit"))
        String.to_integer(Enum.at(opts, limit_idx + 1))
      else
        10
      end

    IO.puts("\nListing HubSpot Contacts (limit: #{limit})\n")

    case get_hubspot_token(user_id) do
      {:ok, token} ->
        url = "https://api.hubapi.com/crm/v3/objects/contacts?limit=#{limit}"

        case Req.get(url, headers: [{"Authorization", "Bearer #{token}"}]) do
          {:ok, %{status: 200, body: data}} ->
            if Enum.empty?(data["results"] || []) do
              IO.puts("  No contacts found")
            else
              Enum.each(data["results"], fn contact ->
                props = contact["properties"]

                IO.puts("  👤 #{props["firstname"]} #{props["lastname"]}")
                IO.puts("     Email: #{props["email"]}")
                IO.puts("     Company: #{props["company"]}")
                IO.puts("     ID: #{contact["id"]}")
                IO.puts("")
              end)

              IO.puts("Total: #{length(data["results"])} contacts")
            end

          {:ok, %{status: status}} ->
            IO.puts("API returned status #{status}")

          {:error, reason} ->
            IO.puts("Request failed: #{inspect(reason)}")
        end

      {:error, reason} ->
        IO.puts("No HubSpot connection: #{inspect(reason)}")
    end
  end

  defp find_contact(email) do
    user_id = get_user_id_from_opts([])

    IO.puts("\n🔍 Finding Contact: #{email}\n")

    case get_hubspot_token(user_id) do
      {:ok, token} ->
        # Search by email
        url = "https://api.hubapi.com/crm/v3/objects/contacts/search"

        body =
          Jason.encode!(%{
            "filterGroups" => [
              %{
                "filters" => [
                  %{
                    "propertyName" => "email",
                    "operator" => "EQ",
                    "value" => email
                  }
                ]
              }
            ]
          })

        headers = [
          {"Authorization", "Bearer #{token}"},
          {"Content-Type", "application/json"}
        ]

        case Req.post(url, headers: headers, body: body) do
          {:ok, %{status: 200, body: data}} ->
            if Enum.empty?(data["results"] || []) do
              IO.puts("  ⚠️  Contact not found")
            else
              contact = List.first(data["results"])
              props = contact["properties"]

              IO.puts("  Found contact:")
              IO.puts("    Name: #{props["firstname"]} #{props["lastname"]}")
              IO.puts("    Email: #{props["email"]}")
              IO.puts("    Company: #{props["company"]}")
              IO.puts("    Phone: #{props["phone"]}")
              IO.puts("    ID: #{contact["id"]}")
              IO.puts("    Created: #{props["createdate"]}")
            end

          {:ok, %{status: status}} ->
            IO.puts("API returned status #{status}")

          {:error, reason} ->
            IO.puts("Request failed: #{inspect(reason)}")
        end

      {:error, reason} ->
        IO.puts("No HubSpot connection: #{inspect(reason)}")
    end
  end

  defp create_contact(email, name, opts) do
    user_id = get_user_id_from_opts(opts)

    [firstname | lastname_parts] = String.split(name, " ")
    lastname = Enum.join(lastname_parts, " ")

    company =
      if Enum.member?(opts, "--company") do
        comp_idx = Enum.find_index(opts, &(&1 == "--company"))
        Enum.at(opts, comp_idx + 1)
      end

    phone =
      if Enum.member?(opts, "--phone") do
        phone_idx = Enum.find_index(opts, &(&1 == "--phone"))
        Enum.at(opts, phone_idx + 1)
      end

    IO.puts("\n➕ Creating HubSpot Contact\n")
    IO.puts("  Name: #{name}")
    IO.puts("  Email: #{email}")
    if company, do: IO.puts("  Company: #{company}")
    if phone, do: IO.puts("  Phone: #{phone}")
    IO.puts("")

    case get_hubspot_token(user_id) do
      {:ok, token} ->
        url = "https://api.hubapi.com/crm/v3/objects/contacts"

        properties = %{
          "email" => email,
          "firstname" => firstname,
          "lastname" => lastname
        }

        properties = if company, do: Map.put(properties, "company", company), else: properties
        properties = if phone, do: Map.put(properties, "phone", phone), else: properties

        body = Jason.encode!(%{"properties" => properties})

        headers = [
          {"Authorization", "Bearer #{token}"},
          {"Content-Type", "application/json"}
        ]

        case Req.post(url, headers: headers, body: body) do
          {:ok, %{status: 201, body: data}} ->
            IO.puts("Contact created successfully!")
            IO.puts("  ID: #{data["id"]}")

          {:ok, %{status: status, body: response_body}} ->
            IO.puts("API returned status #{status}")
            IO.puts("  Response: #{response_body}")

          {:error, reason} ->
            IO.puts("Request failed: #{inspect(reason)}")
        end

      {:error, reason} ->
        IO.puts("No HubSpot connection: #{inspect(reason)}")
    end
  end

  defp add_note(contact_id, text) do
    user_id = get_user_id_from_opts([])

    IO.puts("\n📝 Adding Note to Contact: #{contact_id}\n")

    IO.puts(
      "  Note: #{String.slice(text, 0, 100)}#{if String.length(text) > 100, do: "...", else: ""}\n"
    )

    case get_hubspot_token(user_id) do
      {:ok, token} ->
        url = "https://api.hubapi.com/crm/v3/objects/notes"

        timestamp = DateTime.utc_now() |> DateTime.to_unix(:millisecond)

        body =
          Jason.encode!(%{
            "properties" => %{
              "hs_timestamp" => timestamp,
              "hs_note_body" => text
            },
            "associations" => [
              %{
                "to" => %{"id" => contact_id},
                "types" => [
                  %{
                    "associationCategory" => "HUBSPOT_DEFINED",
                    "associationTypeId" => 202
                  }
                ]
              }
            ]
          })

        headers = [
          {"Authorization", "Bearer #{token}"},
          {"Content-Type", "application/json"}
        ]

        case Req.post(url, headers: headers, body: body) do
          {:ok, %{status: 201, body: data}} ->
            IO.puts("Note added successfully!")
            IO.puts("  Note ID: #{data["id"]}")

          {:ok, %{status: status, body: response_body}} ->
            IO.puts("API returned status #{status}")
            IO.puts("  Response: #{response_body}")

          {:error, reason} ->
            IO.puts("Request failed: #{inspect(reason)}")
        end

      {:error, reason} ->
        IO.puts("No HubSpot connection: #{inspect(reason)}")
    end
  end

  defp get_contact(contact_id) do
    user_id = get_user_id_from_opts([])

    IO.puts("\n👤 Getting Contact: #{contact_id}\n")

    case get_hubspot_token(user_id) do
      {:ok, token} ->
        url =
          "https://api.hubapi.com/crm/v3/objects/contacts/#{contact_id}?properties=firstname,lastname,email,company,phone,createdate,lastmodifieddate"

        case Req.get(url, headers: [{"Authorization", "Bearer #{token}"}]) do
          {:ok, %{status: 200, body: data}} ->
            props = data["properties"]

            IO.puts("  Name: #{props["firstname"]} #{props["lastname"]}")
            IO.puts("  Email: #{props["email"]}")
            IO.puts("  Company: #{props["company"]}")
            IO.puts("  Phone: #{props["phone"]}")
            IO.puts("  Created: #{props["createdate"]}")
            IO.puts("  Modified: #{props["lastmodifieddate"]}")
            IO.puts("  ID: #{data["id"]}")

          {:ok, %{status: 404}} ->
            IO.puts("Contact not found")

          {:ok, %{status: status}} ->
            IO.puts("API returned status #{status}")

          {:error, reason} ->
            IO.puts("Request failed: #{inspect(reason)}")
        end

      {:error, reason} ->
        IO.puts("No HubSpot connection: #{inspect(reason)}")
    end
  end

  defp import_contacts do
    user_id = get_user_id_from_opts([])

    IO.puts("\n📥 Triggering HubSpot Contact Import\n")

    case Jump.Workers.ImportHubspotContacts.perform(%Oban.Job{args: %{"user_id" => user_id}}) do
      :ok ->
        IO.puts("Import job completed successfully!")

      {:error, reason} ->
        IO.puts("Import failed: #{inspect(reason)}")
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

  defp get_hubspot_token(user_id) do
    case Accounts.get_oauth_account(user_id, :hubspot) do
      {:ok, oauth} -> {:ok, oauth.access_token}
      error -> error
    end
  end

  defp show_help do
    IO.puts("""

    HubSpot Test Commands

    List contacts:
      mix test.hubspot list               # List 10 contacts
      mix test.hubspot list --limit 20    # List 20 contacts

    Find contact:
      mix test.hubspot find "user@example.com"

    Create contact:
      mix test.hubspot create "user@example.com" "John Doe" \\
        --company "Acme Inc" \\
        --phone "+1-555-0100"

    Add note:
      mix test.hubspot note <contact_id> "Had a great call today..."

    Get contact:
      mix test.hubspot get <contact_id>

    Import all contacts:
      mix test.hubspot import

    """)
  end
end
