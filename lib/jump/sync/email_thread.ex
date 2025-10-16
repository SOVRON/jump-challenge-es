defmodule Jump.Sync.EmailThread do
  use Ecto.Schema
  import Ecto.Changeset

  schema "email_threads" do
    field :thread_id, :string
    field :last_history_id, :string
    field :snippet, :string
    field :subject, :string
    field :participants, :map
    field :last_message_at, :utc_datetime

    belongs_to :user, Jump.Accounts.User

    timestamps()
  end

  def changeset(email_thread, attrs) do
    email_thread
    |> cast(attrs, [
      :user_id,
      :thread_id,
      :last_history_id,
      :snippet,
      :subject,
      :participants,
      :last_message_at
    ])
    |> validate_required([:user_id, :thread_id])
    |> foreign_key_constraint(:user_id)
    |> unique_constraint([:user_id, :thread_id])
  end
end
