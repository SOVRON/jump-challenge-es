defmodule Jump.Repo.Migrations.RemoveVaultEncryption do
  use Ecto.Migration

  def change do
    alter table(:oauth_accounts) do
      modify :access_token, :text, from: {:binary, Jump.Vault.EncryptedBinary}
      modify :refresh_token, :text, from: {:binary, Jump.Vault.EncryptedBinary}
    end
  end
end
