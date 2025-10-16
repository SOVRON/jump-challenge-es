defmodule Jump.Repo.Migrations.CreateGmailCursorsTable do
  use Ecto.Migration

  def change do
    create table(:gmail_cursors) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :history_id, :string
      add :watch_expiration, :utc_datetime
      add :topic_name, :string

      timestamps()
    end

    create unique_index(:gmail_cursors, [:user_id])
    create index(:gmail_cursors, [:watch_expiration])
  end
end
