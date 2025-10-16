defmodule Jump.Workers.CalendarWatchRenewal do
  @moduledoc """
  Oban worker for renewing Google Calendar watch subscriptions before they expire.
  """

  use Oban.Worker, queue: :sync, max_attempts: 3

  alias Jump.Calendar.Webhooks
  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"webhook_url" => webhook_url}}) do
    Logger.info("Starting calendar watch renewal process")

    # Check and renew expiring webhooks
    Webhooks.check_and_renew_webhooks(webhook_url)

    :ok
  end

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{"user_id" => user_id, "calendar_id" => calendar_id, "webhook_url" => webhook_url}
      }) do
    Logger.info("Renewing calendar watch for user #{user_id}, calendar #{calendar_id}")

    case Webhooks.renew_webhook(user_id, calendar_id, webhook_url) do
      {:ok, _cursor} ->
        Logger.info("Successfully renewed calendar watch for user #{user_id}")
        :ok

      {:error, reason} ->
        Logger.error("Failed to renew calendar watch for user #{user_id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"action" => "cleanup_expired"}}) do
    Logger.info("Cleaning up expired calendar watches")

    # Find and remove expired webhooks
    cleanup_expired_watches()

    :ok
  end

  # Private functions

  defp cleanup_expired_watches() do
    # This would find and clean up expired webhook subscriptions
    # that weren't renewed properly
    Logger.debug("Cleaning up expired calendar watch subscriptions")

    # Implementation would:
    # 1. Find expired cursors in database
    # 2. Attempt to stop the watch via Google API
    # 3. Remove expired cursor records

    :ok
  end
end
