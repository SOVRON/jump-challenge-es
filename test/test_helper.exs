# Compile test support files first
Code.require_file("support/data_case.ex", __DIR__)
Code.require_file("support/conn_case.ex", __DIR__)
Code.require_file("support/unit_case.ex", __DIR__)
Code.require_file("support/test_helpers.ex", __DIR__)

# Compile fixtures
fixtures_path = Path.join(__DIR__, "support/fixtures")

fixtures_path
|> File.ls!()
|> Enum.each(fn file ->
  Code.require_file(Path.join("support/fixtures", file), __DIR__)
end)

ExUnit.start()

# Only setup database sandbox if we can access the repo
# This allows unit tests to run without a database
try do
  Ecto.Adapters.SQL.Sandbox.mode(Jump.Repo, :manual)
rescue
  _ in RuntimeError -> nil
end
