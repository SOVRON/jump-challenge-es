defmodule Jump.AccountsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Jump.Accounts` context.
  """

  def unique_user_email, do: "user#{System.unique_integer()}@example.com"
  def valid_user_password, do: "hello world!"

  def user_fixture(attrs \\ %{}) do
    {:ok, user} =
      attrs
      |> Enum.into(%{
        email: unique_user_email(),
        name: "some name",
        avatar_url: "some avatar_url"
      })
      |> Jump.Accounts.create_user()

    user
  end
end
