defmodule Jump.Repo do
  use Ecto.Repo,
    otp_app: :jump,
    adapter: Ecto.Adapters.Postgres
end
