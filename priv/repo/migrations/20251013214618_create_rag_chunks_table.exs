defmodule Jump.Repo.Migrations.CreateRagChunksTable do
  use Ecto.Migration

  def change do
    create table(:rag_chunks) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :source, :string, null: false
      add :source_id, :string, null: false
      add :person_email, :string
      add :person_name, :string
      add :meta, :jsonb
      add :text, :text, null: false
      add :embedding, :vector, size: 1536

      timestamps()
    end

    create index(:rag_chunks, [:user_id])
    create index(:rag_chunks, [:source])
    create index(:rag_chunks, [:source_id])
    create index(:rag_chunks, [:person_email])
    create index(:rag_chunks, [:inserted_at])

    # Create HNSW index for vector similarity search
    execute "CREATE INDEX rag_chunks_embedding_idx ON rag_chunks USING hnsw (embedding vector_cosine_ops);"
  end

  def down do
    drop table(:rag_chunks)

    # Drop HNSW index for vector similarity search
    execute "DROP INDEX IF EXISTS rag_chunks_embedding_idx;"
  end
end
