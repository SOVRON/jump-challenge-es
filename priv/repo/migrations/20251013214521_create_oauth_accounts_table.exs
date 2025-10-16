defmodule Jump.Repo.Migrations.CreateOauthAccountsTable do
  use Ecto.Migration

  def change do
    create table(:oauth_accounts) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :provider, :string, null: false
      add :access_token, :binary, null: false
      add :refresh_token, :binary
      add :token_type, :string
      add :expires_at, :utc_datetime
      add :scope, :text
      add :external_uid, :string, null: false

      timestamps()
    end

    create index(:oauth_accounts, [:user_id])
    create index(:oauth_accounts, [:provider])
    create unique_index(:oauth_accounts, [:user_id, :provider])
    create index(:oauth_accounts, [:external_uid])
  end
end
