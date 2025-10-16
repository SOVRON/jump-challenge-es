defmodule Jump.Sync.GmailCursor do
  use Ecto.Schema
  import Ecto.Changeset

  schema "gmail_cursors" do
    field :history_id, :string
    field :watch_expiration, :utc_datetime
    field :topic_name, :string

    belongs_to :user, Jump.Accounts.User

    timestamps()
  end

  def changeset(cursor, attrs) do
    cursor
    |> cast(attrs, [:user_id, :history_id, :watch_expiration, :topic_name])
    |> validate_required([:user_id])
    |> foreign_key_constraint(:user_id)
    |> unique_constraint(:user_id)
  end
end
