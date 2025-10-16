defmodule Jump.Repo.Migrations.CreateTasksTable do
  use Ecto.Migration

  def change do
    create table(:tasks) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :status, :string, null: false, default: "queued"
      add :kind, :string, null: false
      add :input, :jsonb
      add :state, :jsonb
      add :result, :jsonb
      add :error, :jsonb
      add :correlation_key, :string

      timestamps()
    end

    create index(:tasks, [:user_id])
    create index(:tasks, [:status])
    create index(:tasks, [:kind])
    create index(:tasks, [:correlation_key])
    create index(:tasks, [:inserted_at])
  end
end
