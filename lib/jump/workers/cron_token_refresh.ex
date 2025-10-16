defmodule Jump.Workers.CronTokenRefresh do
  @moduledoc """
  Cron dispatcher worker that refreshes expiring OAuth tokens.
  Runs hourly to refresh tokens expiring within 60 minutes.
  """

  use Oban.Worker, queue: :default, unique: [period: 60]

  alias Jump.Workers.ObanHelper
  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    Logger.info("Running cron token refresh for users with expiring tokens")

    # Refresh tokens expiring within 60 minutes
    ObanHelper.refresh_expiring_tokens(60)

    :ok
  end
end
