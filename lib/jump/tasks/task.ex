defmodule Jump.Tasks.Task do
  use Ecto.Schema
  import Ecto.Changeset

  schema "tasks" do
    field :status, :string, default: "queued"
    field :kind, :string
    field :input, :map
    field :state, :map
    field :result, :map
    field :error, :map
    field :correlation_key, :string

    belongs_to :user, Jump.Accounts.User
    has_many :messages, Jump.Messaging.Message

    timestamps()
  end

  def changeset(task, attrs) do
    task
    |> cast(attrs, [:user_id, :status, :kind, :input, :state, :result, :error, :correlation_key])
    |> validate_required([:user_id, :status, :kind])
    |> validate_inclusion(:status, ["queued", "running", "waiting", "done", "failed", "cancelled"])
    |> foreign_key_constraint(:user_id)
  end
end
