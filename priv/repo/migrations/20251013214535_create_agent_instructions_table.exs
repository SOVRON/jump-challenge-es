defmodule Jump.Repo.Migrations.CreateAgentInstructionsTable do
  use Ecto.Migration

  def change do
    create table(:agent_instructions) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :title, :string, null: false
      add :content, :text, null: false
      add :enabled, :boolean, default: true, null: false

      timestamps()
    end

    create index(:agent_instructions, [:user_id])
    create index(:agent_instructions, [:enabled])
  end
end
