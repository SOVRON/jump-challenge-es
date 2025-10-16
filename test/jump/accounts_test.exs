defmodule Jump.AccountsTest do
  use Jump.DataCase

  @moduletag :db

  alias Jump.Accounts

  describe "users" do
    alias Jump.Accounts.User

    import Jump.AccountsFixtures

    @invalid_attrs %{email: nil, name: nil, avatar_url: nil}

    test "list_users/0 returns all users" do
      user = user_fixture()
      assert Accounts.list_users() == [user]
    end

    test "get_user!/1 returns the user with given id" do
      user = user_fixture()
      assert Accounts.get_user!(user.id) == user
    end

    test "get_user_by_email/1 returns the user with given email" do
      user = user_fixture()
      assert Accounts.get_user_by_email(user.email) == user
      assert Accounts.get_user_by_email("nonexistent@example.com") == nil
    end

    test "create_user/1 with valid data creates a user" do
      valid_attrs = %{email: "test@example.com", name: "some name", avatar_url: "some avatar_url"}

      assert {:ok, %User{} = user} = Accounts.create_user(valid_attrs)
      assert user.email == "test@example.com"
      assert user.name == "some name"
      assert user.avatar_url == "some avatar_url"
    end

    test "create_user/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Accounts.create_user(@invalid_attrs)
    end

    test "update_user/2 with valid data updates the user" do
      user = user_fixture()

      update_attrs = %{
        email: "updated@example.com",
        name: "some updated name",
        avatar_url: "some updated avatar_url"
      }

      assert {:ok, %User{} = user} = Accounts.update_user(user, update_attrs)
      assert user.email == "updated@example.com"
      assert user.name == "some updated name"
      assert user.avatar_url == "some updated avatar_url"
    end

    test "update_user/2 with invalid data returns error changeset" do
      user = user_fixture()
      assert {:error, %Ecto.Changeset{}} = Accounts.update_user(user, @invalid_attrs)
      assert user == Accounts.get_user!(user.id)
    end

    test "delete_user/1 deletes the user" do
      user = user_fixture()
      assert {:ok, %User{}} = Accounts.delete_user(user)
      assert_raise Ecto.NoResultsError, fn -> Accounts.get_user!(user.id) end
    end

    test "change_user/1 returns a user changeset" do
      user = user_fixture()
      assert %Ecto.Changeset{} = Accounts.change_user(user)
    end
  end
end
