defmodule Jump.Accounts do
  @moduledoc """
  The Accounts context handles user management and OAuth accounts.
  """

  import Ecto.Query, warn: false
  alias Jump.Repo

  alias Jump.Accounts.User
  alias Jump.Accounts.OAuthAccount

  def list_users do
    Repo.all(User)
  end

  def get_user!(id), do: Repo.get!(User, id)

  def get_user(id), do: Repo.get(User, id)

  def get_user_by_email(email) when is_binary(email) do
    Repo.get_by(User, email: email)
  end

  def create_user(attrs \\ %{}) do
    %User{}
    |> User.changeset(attrs)
    |> Repo.insert()
  end

  def update_user(%User{} = user, attrs) do
    user
    |> User.changeset(attrs)
    |> Repo.update()
  end

  def delete_user(%User{} = user) do
    Repo.delete(user)
  end

  def change_user(%User{} = user, attrs \\ %{}) do
    User.changeset(user, attrs)
  end

  def get_or_create_user_by_email(email, attrs \\ %{}) do
    case get_user_by_email(email) do
      nil ->
        create_user(Map.merge(attrs, %{email: email}))

      user ->
        {:ok, user}
    end
  end

  # OAuth Account functions
  def list_oauth_accounts(user_id) do
    OAuthAccount
    |> where([oa], oa.user_id == ^user_id)
    |> Repo.all()
  end

  def get_oauth_account!(id), do: Repo.get!(OAuthAccount, id)

  def get_oauth_account_by_provider(user_id, provider) do
    Repo.get_by(OAuthAccount, user_id: user_id, provider: provider)
  end

  def get_oauth_account(user_id, provider) do
    case get_oauth_account_by_provider(user_id, provider) do
      nil -> {:error, :not_found}
      oauth_account -> {:ok, oauth_account}
    end
  end

  def create_oauth_account(attrs \\ %{}) do
    %OAuthAccount{}
    |> OAuthAccount.changeset(attrs)
    |> Repo.insert()
  end

  def upsert_oauth_account(attrs) do
    %OAuthAccount{}
    |> OAuthAccount.changeset(attrs)
    |> Repo.insert(
      on_conflict: :replace_all,
      conflict_target: [:user_id, :provider]
    )
  end

  def update_oauth_account(%OAuthAccount{} = oauth_account, attrs) do
    oauth_account
    |> OAuthAccount.changeset(attrs)
    |> Repo.update()
  end

  def delete_oauth_account(%OAuthAccount{} = oauth_account) do
    Repo.delete(oauth_account)
  end

  def change_oauth_account(%OAuthAccount{} = oauth_account, attrs \\ %{}) do
    OAuthAccount.changeset(oauth_account, attrs)
  end

  def get_user_oauth_token(user_id, provider) do
    OAuthAccount
    |> where([oa], oa.user_id == ^user_id and oa.provider == ^provider)
    |> Repo.one()
  end
end
