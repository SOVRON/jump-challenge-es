defmodule Jump.Auth.GoogleTokens do
  @moduledoc """
  Handles Google OAuth token refresh operations.
  """

  alias Jump.Accounts
  alias Jump.Accounts.OAuthAccount
  require Logger

  @refresh_threshold_minutes 5

  @doc """
  Refreshes the Google OAuth token if it's expiring within the threshold.
  """
  def refresh_if_needed(%OAuthAccount{provider: :google} = oauth_account) do
    if should_refresh?(oauth_account) do
      refresh_token(oauth_account)
    else
      {:ok, oauth_account}
    end
  end

  def refresh_if_needed(_), do: {:error, :not_google_provider}

  @doc """
  Refreshes all expiring Google tokens for all users.
  """
  def refresh_expiring_tokens do
    import Ecto.Query

    cutoff = refresh_cutoff()

    OAuthAccount
    |> where([oa], oa.provider == :google and oa.expires_at <= ^cutoff)
    |> Jump.Repo.all()
    |> Enum.each(&refresh_token/1)
  end

  # Private functions

  defp should_refresh?(%OAuthAccount{expires_at: expires_at}) do
    DateTime.compare(expires_at, refresh_cutoff()) != :gt
  end

  defp refresh_cutoff do
    DateTime.add(DateTime.utc_now(), @refresh_threshold_minutes * 60, :second)
  end

  defp refresh_token(%OAuthAccount{refresh_token: nil} = oauth_account) do
    Logger.error("No refresh token available for Google OAuth account #{oauth_account.id}")
    {:error, :no_refresh_token}
  end

  defp refresh_token(%OAuthAccount{refresh_token: refresh_token} = oauth_account) do
    client = build_oauth_client(refresh_token)

    case OAuth2.Client.get_token(client, [], refresh_token: refresh_token) do
      {:ok, %{token: access_token, refresh_token: new_refresh_token, expires_at: expires_at}} ->
        update_oauth_account(oauth_account, %{
          access_token: access_token,
          refresh_token: new_refresh_token || refresh_token,
          expires_at: DateTime.from_unix!(expires_at)
        })

      {:error, reason} ->
        Logger.error(
          "Failed to refresh Google token for account #{oauth_account.id}: #{inspect(reason)}"
        )

        {:error, reason}
    end
  end

  defp build_oauth_client(refresh_token) do
    OAuth2.Client.new(
      strategy: OAuth2.Strategy.Refresh,
      client_id: System.get_env("GOOGLE_CLIENT_ID"),
      client_secret: System.get_env("GOOGLE_CLIENT_SECRET"),
      site: "https://oauth2.googleapis.com",
      refresh_token: refresh_token
    )
  end

  defp update_oauth_account(oauth_account, attrs) do
    case Accounts.update_oauth_account(oauth_account, attrs) do
      {:ok, updated_account} ->
        Logger.info("Successfully refreshed Google token for account #{updated_account.id}")
        {:ok, updated_account}

      {:error, changeset} ->
        Logger.error(
          "Failed to update Google OAuth account #{oauth_account.id}: #{inspect(changeset.errors)}"
        )

        {:error, changeset}
    end
  end
end
