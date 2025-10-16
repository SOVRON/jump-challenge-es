defmodule Jump.Agents.Instruction do
  use Ecto.Schema
  import Ecto.Changeset

  schema "agent_instructions" do
    field :title, :string
    field :content, :string
    field :enabled, :boolean, default: true

    belongs_to :user, Jump.Accounts.User

    timestamps()
  end

  def changeset(instruction, attrs) do
    instruction
    |> cast(attrs, [:user_id, :title, :content, :enabled])
    |> validate_required([:user_id, :title, :content])
    |> foreign_key_constraint(:user_id)
  end
end
