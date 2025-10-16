defmodule Jump.Repo.Migrations.CreateEmailThreadsTable do
  use Ecto.Migration

  def change do
    create table(:email_threads) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :thread_id, :string, null: false
      add :last_history_id, :string
      add :snippet, :text
      add :subject, :string
      add :participants, :jsonb
      add :last_message_at, :utc_datetime

      timestamps()
    end

    create index(:email_threads, [:user_id])
    create unique_index(:email_threads, [:user_id, :thread_id])
    create index(:email_threads, [:last_message_at])
  end
end
