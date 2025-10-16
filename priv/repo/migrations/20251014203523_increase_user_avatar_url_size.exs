defmodule Jump.Repo.Migrations.IncreaseUserAvatarUrlSize do
  use Ecto.Migration

  def change do
    alter table(:users) do
      modify :avatar_url, :text
    end
  end
end
