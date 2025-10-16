defmodule JumpWeb.HubspotWebhookController do
  use JumpWeb, :controller

  alias Jump.Workers.HubspotWebhookHandler
  alias Jump.Web.HubspotSignatureValidator
  require Logger

  # Webhooks are API endpoints, skip CSRF protection by using :api pipeline

  def create(conn, %{"eventType" => _event_type} = params) do
    client_secret = System.get_env("HUBSPOT_CLIENT_SECRET")

    case validate_webhook(conn, params, client_secret) do
      :ok ->
        # Enqueue webhook processing
        case enqueue_webhook_processing(params) do
          {:ok, _job} ->
            send_resp(conn, 200, "Webhook received and queued for processing")

          {:error, reason} ->
            Logger.error("Failed to enqueue HubSpot webhook: #{inspect(reason)}")
            send_resp(conn, 500, "Failed to process webhook")
        end

      {:error, :invalid_signature} ->
        Logger.warning("Invalid HubSpot webhook signature received")
        send_resp(conn, 401, "Invalid signature")

      {:error, :invalid_timestamp} ->
        Logger.warning("Invalid timestamp in HubSpot webhook")
        send_resp(conn, 401, "Invalid timestamp")

      {:error, reason} ->
        Logger.error("HubSpot webhook validation failed: #{inspect(reason)}")
        send_resp(conn, 400, "Bad request")
    end
  end

  def create(conn, _params) do
    send_resp(conn, 400, "Invalid webhook payload")
  end

  # Private functions

  defp validate_webhook(conn, params, client_secret) do
    with {:ok, signature} <- get_request_header(conn, "x-hubspot-signature-v3"),
         {:ok, timestamp_str} <- get_request_header(conn, "x-hubspot-request-timestamp"),
         {timestamp_unix, ""} <- Integer.parse(timestamp_str),
         :ok <- validate_timestamp(timestamp_unix),
         :ok <- validate_signature(conn, params, timestamp_unix, signature, client_secret) do
      :ok
    else
      _ -> {:error, :validation_failed}
    end
  end

  defp get_request_header(conn, header_name) do
    case get_req_header(conn, header_name) do
      [value] when value != "" -> {:ok, value}
      _ -> {:error, :missing_header}
    end
  end

  defp validate_timestamp(timestamp_unix) do
    if HubspotSignatureValidator.valid_timestamp?(timestamp_unix) do
      :ok
    else
      {:error, :invalid_timestamp}
    end
  end

  defp validate_signature(conn, _params, timestamp_unix, signature, client_secret) do
    method = conn.method |> String.upcase()
    url = get_full_url(conn)
    body = conn |> read_body() |> elem(1) |> to_string()

    if HubspotSignatureValidator.validate_signature(
         method,
         url,
         body,
         timestamp_unix,
         signature,
         client_secret
       ) do
      :ok
    else
      {:error, :invalid_signature}
    end
  end

  defp get_full_url(conn) do
    scheme = if conn.scheme == :https, do: "https", else: "http"
    host = conn.host
    port = conn.port
    path = conn.request_path

    url = "#{scheme}://#{host}"

    full_url =
      cond do
        (scheme == "https" and port == 443) or (scheme == "http" and port == 80) ->
          url <> path

        true ->
          url <> ":#{port}" <> path
      end

    full_url
  end

  defp enqueue_webhook_processing(params) do
    %{"args" => params}
    |> HubspotWebhookHandler.new()
    |> Oban.insert()
  end
end
