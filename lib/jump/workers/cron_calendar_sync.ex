defmodule Jump.Workers.CronCalendarSync do
  @moduledoc """
  Cron dispatcher worker that syncs calendars for all connected users.
  Runs every 10 minutes to check for new calendar events.
  """

  use Oban.Worker, queue: :sync, unique: [period: 60]

  alias Jump.Workers.ObanHelper
  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    Logger.info("Running cron calendar sync for all users")

    # Get all users with Google OAuth and enqueue calendar sync
    ObanHelper.sync_all_users_provider(Jump.Workers.CalendarSync, :google)

    :ok
  end
end
