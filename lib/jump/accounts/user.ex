defmodule Jump.Accounts.User do
  use Ecto.Schema
  import Ecto.Changeset

  schema "users" do
    field :email, :string
    field :name, :string
    field :avatar_url, :string

    has_many :oauth_accounts, Jump.Accounts.OAuthAccount
    has_many :agent_instructions, Jump.Agents.Instruction
    has_many :tasks, Jump.Tasks.Task
    has_many :messages, Jump.Messaging.Message
    has_many :rag_chunks, Jump.RAG.Chunk
    has_many :email_threads, Jump.Sync.EmailThread
    has_many :calendar_cursors, Jump.Sync.CalendarCursor
    has_many :gmail_cursors, Jump.Sync.GmailCursor

    timestamps()
  end

  def changeset(user, attrs) do
    user
    |> cast(attrs, [:email, :name, :avatar_url])
    |> validate_required([:email])
    |> validate_format(:email, ~r/@/)
    |> unique_constraint(:email)
  end
end
