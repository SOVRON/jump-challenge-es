defmodule Jump.Repo.Migrations.IncreaseOauthAccountFieldSizes do
  use Ecto.Migration

  def change do
    alter table(:oauth_accounts) do
      modify :external_uid, :text, null: false
    end
  end
end
