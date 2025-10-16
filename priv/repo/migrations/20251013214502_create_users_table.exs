defmodule Jump.Repo.Migrations.CreateUsersTable do
  use Ecto.Migration

  def change do
    create table(:users) do
      add :email, :string, null: false
      add :name, :string
      add :avatar_url, :string

      timestamps()
    end

    create unique_index(:users, [:email])
  end
end
