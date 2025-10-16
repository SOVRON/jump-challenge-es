defmodule Jump.Workers.RefreshTokens do
  @moduledoc """
  Oban worker for refreshing expiring OAuth tokens.
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"action" => "refresh_expiring"}}) do
    Jump.Auth.GoogleTokens.refresh_expiring_tokens()
    :ok
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"action" => "refresh_user", "user_id" => user_id}}) do
    case Jump.Accounts.get_oauth_account(user_id, :google) do
      {:ok, oauth_account} ->
        Jump.Auth.GoogleTokens.refresh_if_needed(oauth_account)
        :ok

      {:error, :not_found} ->
        :ok
    end
  end
end
