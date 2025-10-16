defmodule Jump.Sync.CalendarCursor do
  use Ecto.Schema
  import Ecto.Changeset

  schema "calendar_cursors" do
    field :calendar_id, :string
    field :sync_token, :string
    field :resource_id, :string
    field :channel_id, :string
    field :channel_expiration, :utc_datetime

    belongs_to :user, Jump.Accounts.User

    timestamps()
  end

  def changeset(cursor, attrs) do
    cursor
    |> cast(attrs, [
      :user_id,
      :calendar_id,
      :sync_token,
      :resource_id,
      :channel_id,
      :channel_expiration
    ])
    |> validate_required([:user_id, :calendar_id])
    |> foreign_key_constraint(:user_id)
    |> unique_constraint([:user_id, :calendar_id])
  end
end
