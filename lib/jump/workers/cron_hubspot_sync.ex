defmodule Jump.Workers.CronHubspotSync do
  @moduledoc """
  Cron dispatcher worker that syncs HubSpot contacts for all connected users.
  Runs periodically to index contacts for RAG.
  """

  use Oban.Worker, queue: :ingest, unique: [period: 60]

  alias Jump.Workers.ObanHelper
  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    Logger.info("Running cron HubSpot sync for all users")

    # Get all users with HubSpot OAuth and enqueue contact import
    ObanHelper.sync_all_users_provider(Jump.Workers.ImportHubspotContacts, :hubspot)

    :ok
  end
end
