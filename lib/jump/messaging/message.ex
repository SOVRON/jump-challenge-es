defmodule Jump.Messaging.Message do
  use Ecto.Schema
  import Ecto.Changeset

  schema "messages" do
    field :role, :string
    field :content, :string
    field :tool_name, :string
    field :tool_args, :map
    field :tool_result, :map
    field :thread_id, :string

    belongs_to :user, Jump.Accounts.User
    belongs_to :task, Jump.Tasks.Task

    timestamps()
  end

  def changeset(message, attrs) do
    message
    |> cast(attrs, [
      :user_id,
      :task_id,
      :role,
      :content,
      :tool_name,
      :tool_args,
      :tool_result,
      :thread_id
    ])
    |> validate_required([:user_id, :role])
    |> validate_inclusion(:role, ["user", "assistant", "tool", "system"])
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:task_id)
  end
end
