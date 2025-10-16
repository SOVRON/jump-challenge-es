defmodule JumpWeb.CalendarWebhookController do
  use JumpWeb, :controller

  alias Jump.Calendar.Webhooks
  alias Jump.Workers.CalendarSync
  require Logger

  # Calendar webhooks are API endpoints, skip CSRF protection by using :api pipeline

  def create(conn, _params) do
    # Extract relevant headers
    headers = extract_webhook_headers(conn)

    # Read the request body
    {:ok, body, conn} = read_body(conn)

    # Validate webhook notification
    case Webhooks.validate_webhook_notification(headers, body) do
      {:ok, notification_data} ->
        # Process the notification asynchronously
        case enqueue_webhook_processing(notification_data) do
          {:ok, _job} ->
            # Return 200 OK immediately
            send_resp(conn, 200, "Webhook received and queued for processing")

          {:error, reason} ->
            Logger.error("Failed to enqueue calendar webhook: #{inspect(reason)}")
            send_resp(conn, 500, "Failed to process webhook")
        end

      {:error, :webhook_not_found} ->
        Logger.warning("Calendar webhook not found for channel")
        send_resp(conn, 404, "Webhook not found")

      {:error, :missing_header} ->
        Logger.warning("Missing required headers in calendar webhook")
        send_resp(conn, 400, "Missing required headers")

      {:error, reason} ->
        Logger.error("Calendar webhook validation failed: #{inspect(reason)}")
        send_resp(conn, 400, "Bad request")
    end
  end

  # Handle webhook verification requests (Google may send verification)
  def create(conn, %{"challenge" => challenge}) do
    # Respond to webhook verification challenge
    send_resp(conn, 200, challenge)
  end

  # Private functions

  defp extract_webhook_headers(conn) do
    relevant_headers = [
      "x-goog-channel-id",
      "x-goog-resource-id",
      "x-goog-resource-state",
      "x-goog-resource-uri",
      "x-goog-message-number",
      "x-goog-changed"
    ]

    Enum.map(relevant_headers, fn header ->
      case get_req_header(conn, header) do
        [value] -> {header, value}
        [] -> {header, nil}
      end
    end)
  end

  defp enqueue_webhook_processing(notification_data) do
    # Enqueue a job to process the webhook notification
    CalendarSync.new(%{
      "user_id" => notification_data.cursor.user_id,
      "calendar_id" => notification_data.cursor.calendar_id,
      "notification_data" => notification_data,
      "triggered_by" => "webhook"
    })
    |> Oban.insert()
  end
end
