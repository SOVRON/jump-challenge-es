defmodule Jump.Workers.CronCalendarWatchRenewal do
  @moduledoc """
  Cron dispatcher worker that renews calendar watch subscriptions.
  Runs every 6 hours to keep webhook subscriptions active.
  """

  use Oban.Worker, queue: :default, unique: [period: 60]

  alias Jump.Workers.ObanHelper
  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    Logger.info("Running cron calendar watch renewal for all users")

    # Renew calendar watches for all users
    ObanHelper.renew_all_calendar_watches()

    :ok
  end
end
