defmodule Jump.Workers.ObanHelper do
  @moduledoc """
  Helper utilities for Oban workers to manage recurring tasks across multiple users.
  """

  import Ecto.Query
  alias Jump.Repo
  alias Jump.Accounts.OAuthAccount
  require Logger

  @doc """
  Get all users with a specific OAuth provider connected.
  """
  def get_users_with_provider(provider) do
    OAuthAccount
    |> where([oa], oa.provider == ^provider)
    |> select([oa], oa.user_id)
    |> distinct(true)
    |> Repo.all()
  end

  @doc """
  Enqueue sync jobs for all users with a given provider.
  Used by cron jobs to keep all user data in sync.
  """
  def sync_all_users_provider(worker_module, provider, args \\ %{}) do
    users = get_users_with_provider(provider)
    Logger.info("Enqueuing #{worker_module} jobs for #{length(users)} users with #{provider}")

    Enum.each(users, fn user_id ->
      job_args = Map.put(args, "user_id", user_id)

      job_args
      |> worker_module.new()
      |> Oban.insert()
    end)

    :ok
  end

  @doc """
  Enqueue token refresh jobs for all users with OAuth tokens.
  """
  def refresh_expiring_tokens(threshold_minutes \\ 60) do
    # Get OAuth accounts where token expires within threshold
    cutoff_time = DateTime.add(DateTime.utc_now(), threshold_minutes * 60, :second)

    OAuthAccount
    |> where([oa], oa.expires_at <= ^cutoff_time)
    |> where([oa], oa.expires_at > ^DateTime.utc_now())
    |> select([oa], oa.user_id)
    |> distinct(true)
    |> Repo.all()
    |> Enum.each(fn user_id ->
      %{"user_id" => user_id}
      |> Jump.Workers.RefreshTokens.new()
      |> Oban.insert()
    end)

    :ok
  end

  @doc """
  Enqueue calendar watch renewal for all users.
  """
  def renew_all_calendar_watches do
    users = get_users_with_provider(:google)
    Logger.info("Enqueuing calendar watch renewals for #{length(users)} users")

    Enum.each(users, fn user_id ->
      %{"user_id" => user_id}
      |> Jump.Workers.CalendarWatchRenewal.new()
      |> Oban.insert()
    end)

    :ok
  end
end
