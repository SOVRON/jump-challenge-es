defmodule Jump.Accounts.OAuthAccount do
  use Ecto.Schema
  import Ecto.Changeset

  schema "oauth_accounts" do
    field :provider, Ecto.Enum, values: [:google, :hubspot]
    field :access_token, :string
    field :refresh_token, :string
    field :token_type, :string
    field :expires_at, :utc_datetime
    field :scope, :string
    field :external_uid, :string

    belongs_to :user, Jump.Accounts.User

    timestamps()
  end

  def changeset(oauth_account, attrs) do
    oauth_account
    |> cast(attrs, [
      :user_id,
      :provider,
      :access_token,
      :refresh_token,
      :token_type,
      :expires_at,
      :scope,
      :external_uid
    ])
    |> validate_required([:user_id, :provider, :access_token, :external_uid])
    |> foreign_key_constraint(:user_id)
    |> unique_constraint([:user_id, :provider])
  end
end
