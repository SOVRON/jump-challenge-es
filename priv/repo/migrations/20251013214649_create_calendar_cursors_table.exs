defmodule Jump.Repo.Migrations.CreateCalendarCursorsTable do
  use Ecto.Migration

  def change do
    create table(:calendar_cursors) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :calendar_id, :string, null: false
      add :sync_token, :string
      add :resource_id, :string
      add :channel_id, :string
      add :channel_expiration, :utc_datetime

      timestamps()
    end

    create index(:calendar_cursors, [:user_id])
    create unique_index(:calendar_cursors, [:user_id, :calendar_id])
    create index(:calendar_cursors, [:channel_expiration])
  end
end
