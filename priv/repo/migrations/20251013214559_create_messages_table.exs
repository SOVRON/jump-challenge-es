defmodule Jump.Repo.Migrations.CreateMessagesTable do
  use Ecto.Migration

  def change do
    create table(:messages) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :role, :string, null: false
      add :content, :text
      add :tool_name, :string
      add :tool_args, :jsonb
      add :tool_result, :jsonb
      add :task_id, references(:tasks, on_delete: :nilify_all)
      add :thread_id, :string

      timestamps()
    end

    create index(:messages, [:user_id])
    create index(:messages, [:role])
    create index(:messages, [:task_id])
    create index(:messages, [:thread_id])
    create index(:messages, [:inserted_at])
  end
end
