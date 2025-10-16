defmodule Jump.Workers.CronGmailSync do
  @moduledoc """
  Cron dispatcher worker that syncs Gmail for all connected users.
  Runs every 5 minutes to check for new emails.
  """

  use Oban.Worker, queue: :sync, unique: [period: 60]

  alias Jump.Workers.ObanHelper
  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    Logger.info("Running cron Gmail sync for all users")

    # Get all users with Google OAuth and enqueue history sync
    ObanHelper.sync_all_users_provider(Jump.Workers.GmailHistorySync, :google)

    :ok
  end
end
