defmodule Jump.RAG.Chunk do
  use Ecto.Schema
  import Ecto.Changeset

  schema "rag_chunks" do
    field :source, :string
    field :source_id, :string
    field :person_email, :string
    field :person_name, :string
    field :meta, :map
    field :text, :string
    field :embedding, Pgvector.Ecto.Vector

    belongs_to :user, Jump.Accounts.User

    timestamps()
  end

  def changeset(chunk, attrs) do
    chunk
    |> cast(attrs, [
      :user_id,
      :source,
      :source_id,
      :person_email,
      :person_name,
      :meta,
      :text,
      :embedding
    ])
    |> validate_required([:user_id, :source, :source_id, :text])
    |> validate_inclusion(:source, ["gmail", "hubspot_contact", "hubspot_note"])
    |> foreign_key_constraint(:user_id)
  end
end
