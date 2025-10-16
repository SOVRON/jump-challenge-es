defmodule Jump.Workers.HubspotWebhookHandler do
  @moduledoc """
  Oban worker for processing HubSpot webhook events.
  """

  use Oban.Worker, queue: :webhooks, max_attempts: 3

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: webhook_payload}) do
    case process_webhook(webhook_payload) do
      :ok ->
        Logger.info("Successfully processed HubSpot webhook")
        :ok

      {:error, reason} ->
        Logger.error("Failed to process HubSpot webhook: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Private functions

  defp process_webhook(%{"eventType" => event_type} = payload) do
    case event_type do
      "contact.creation" ->
        handle_contact_creation(payload)

      "contact.propertyChange" ->
        handle_contact_update(payload)

      "contact.deletion" ->
        handle_contact_deletion(payload)

      _ ->
        Logger.info("Unhandled HubSpot event type: #{event_type}")
        :ok
    end
  end

  defp process_webhook(_payload) do
    Logger.warning("Invalid webhook payload structure")
    {:error, :invalid_payload}
  end

  defp handle_contact_creation(%{"objectId" => contact_id, "properties" => properties}) do
    email = get_property_value(properties, "email")
    name = build_name_from_properties(properties)

    Logger.info("HubSpot contact created: #{contact_id}, email: #{email}, name: #{name}")

    # Here you can add logic to:
    # 1. Store the contact locally
    # 2. Trigger automation rules
    # 3. Send welcome emails, etc.

    :ok
  end

  defp handle_contact_update(%{"objectId" => contact_id, "properties" => properties}) do
    Logger.info("HubSpot contact updated: #{contact_id}")

    # Handle contact property changes
    Enum.each(properties, fn property ->
      handle_property_change(contact_id, property)
    end)

    :ok
  end

  defp handle_contact_deletion(%{"objectId" => contact_id}) do
    Logger.info("HubSpot contact deleted: #{contact_id}")

    # Handle contact deletion locally
    :ok
  end

  defp handle_property_change(contact_id, %{"name" => property_name, "value" => value}) do
    Logger.debug("Contact #{contact_id} property #{property_name} changed to: #{value}")

    # Add specific logic for important property changes
    case property_name do
      "email" -> handle_email_change(contact_id, value)
      "lifecyclestage" -> handle_lifecycle_stage_change(contact_id, value)
      _ -> :ok
    end
  end

  defp handle_email_change(contact_id, new_email) do
    Logger.info("Contact #{contact_id} email changed to: #{new_email}")
    # Add logic for email change handling
  end

  defp handle_lifecycle_stage_change(contact_id, new_stage) do
    Logger.info("Contact #{contact_id} lifecycle stage changed to: #{new_stage}")
    # Add logic for lifecycle stage changes (e.g., became a customer)
  end

  defp get_property_value(properties, property_name) do
    case Enum.find(properties, fn %{"name" => name} -> name == property_name end) do
      %{"value" => value} -> value
      _ -> nil
    end
  end

  defp build_name_from_properties(properties) do
    first_name = get_property_value(properties, "firstname") || ""
    last_name = get_property_value(properties, "lastname") || ""

    case {first_name, last_name} do
      {"", ""} -> get_property_value(properties, "email") || "Unknown"
      {first, ""} -> first
      {"", last} -> last
      {first, last} -> "#{first} #{last}"
    end
  end
end
