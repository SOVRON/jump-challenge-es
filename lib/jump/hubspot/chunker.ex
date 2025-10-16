defmodule Jump.HubSpot.Chunker do
  @moduledoc """
  Chunks HubSpot contacts and notes for RAG pipeline.
  Converts contact information into searchable chunks.
  """

  @doc """
  Create RAG chunks from HubSpot contact data.
  """
  def create_contact_chunks(contact_id, properties, user_id) do
    text = format_contact_text(contact_id, properties)

    if String.length(text) > 0 do
      email = get_property_value(properties, "email")

      name =
        get_property_value(properties, "firstname") || get_property_value(properties, "lastname") ||
          email

      [
        %{
          user_id: user_id,
          source: "hubspot_contact",
          source_id: contact_id,
          text: text,
          meta: extract_contact_metadata(contact_id, properties),
          person_email: email,
          person_name: name
        }
      ]
    else
      []
    end
  end

  @doc """
  Create RAG chunks from HubSpot note/note data.
  """
  def create_note_chunks(note_id, contact_id, note_text, user_id, metadata \\ %{}) do
    if String.length(note_text) > 0 do
      [
        %{
          user_id: user_id,
          source: "hubspot_note",
          source_id: note_id,
          text: note_text,
          meta: extract_note_metadata(note_id, contact_id, metadata),
          person_email: Map.get(metadata, :person_email),
          person_name: Map.get(metadata, :person_name) || Map.get(metadata, :contact_name)
        }
      ]
    else
      []
    end
  end

  # Private helper functions

  defp format_contact_text(contact_id, properties) do
    parts = [
      format_name(properties),
      format_email(properties),
      format_phone(properties),
      format_company(properties),
      format_job_title(properties),
      format_lifecycle_stage(properties),
      format_notes(properties)
    ]

    parts
    |> Enum.filter(&(&1 && String.length(&1) > 0))
    |> Enum.join("\n\n")
  end

  defp format_name(properties) do
    first_name = get_property_value(properties, "firstname") || ""
    last_name = get_property_value(properties, "lastname") || ""

    case {String.trim(first_name), String.trim(last_name)} do
      {"", ""} -> nil
      {first, ""} -> "Contact: #{first}"
      {"", last} -> "Contact: #{last}"
      {first, last} -> "Contact: #{first} #{last}"
    end
  end

  defp format_email(properties) do
    case get_property_value(properties, "email") do
      email when is_binary(email) and byte_size(email) > 0 -> "Email: #{email}"
      _ -> nil
    end
  end

  defp format_phone(properties) do
    case get_property_value(properties, "phone") do
      phone when is_binary(phone) and byte_size(phone) > 0 -> "Phone: #{phone}"
      _ -> nil
    end
  end

  defp format_company(properties) do
    case get_property_value(properties, "company") do
      company when is_binary(company) and byte_size(company) > 0 -> "Company: #{company}"
      _ -> nil
    end
  end

  defp format_job_title(properties) do
    case get_property_value(properties, "jobtitle") do
      title when is_binary(title) and byte_size(title) > 0 -> "Job Title: #{title}"
      _ -> nil
    end
  end

  defp format_lifecycle_stage(properties) do
    case get_property_value(properties, "lifecyclestage") do
      stage when is_binary(stage) and byte_size(stage) > 0 -> "Lifecycle Stage: #{stage}"
      _ -> nil
    end
  end

  defp format_notes(properties) do
    # Combine notes/notes_and_attachments
    notes =
      [
        get_property_value(properties, "notes"),
        get_property_value(properties, "notes_and_attachments")
      ]
      |> Enum.filter(&(&1 && String.length(&1) > 0))
      |> Enum.join("\n")

    if String.length(notes) > 0 do
      notes |> String.slice(0, 500)
    else
      nil
    end
  end

  defp extract_contact_metadata(contact_id, properties) do
    %{
      contact_id: contact_id,
      email: get_property_value(properties, "email"),
      first_name: get_property_value(properties, "firstname"),
      last_name: get_property_value(properties, "lastname"),
      phone: get_property_value(properties, "phone"),
      company: get_property_value(properties, "company"),
      job_title: get_property_value(properties, "jobtitle"),
      lifecycle_stage: get_property_value(properties, "lifecyclestage"),
      hs_lead_status: get_property_value(properties, "hs_lead_status"),
      source: get_property_value(properties, "hs_lead_status"),
      create_date: get_property_value(properties, "createdate"),
      update_date: get_property_value(properties, "lastmodifieddate"),
      associated_deals: get_property_value(properties, "hs_analytics_num_deals"),
      website_url: get_property_value(properties, "website"),
      country: get_property_value(properties, "country"),
      state: get_property_value(properties, "state"),
      city: get_property_value(properties, "city")
    }
  end

  defp extract_note_metadata(note_id, contact_id, metadata) do
    Map.merge(metadata, %{
      note_id: note_id,
      contact_id: contact_id,
      created_at: DateTime.utc_now()
    })
  end

  defp get_property_value(properties, property_name) when is_map(properties) do
    properties[property_name]
  end

  defp get_property_value(properties, property_name) when is_list(properties) do
    case Enum.find(properties, fn %{"name" => name} -> name == property_name end) do
      %{"value" => value} -> value
      _ -> nil
    end
  end

  defp get_property_value(_properties, _property_name), do: nil
end
