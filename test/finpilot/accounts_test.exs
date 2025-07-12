defmodule Finpilot.AccountsTest do
  use Finpilot.DataCase

  alias Finpilot.Accounts

  describe "users" do
    alias Finpilot.Accounts.User

    import Finpilot.AccountsFixtures

    @invalid_attrs %{name: nil, username: nil, email: nil, picture: nil, verified: nil, google_access_token: nil, google_refresh_token: nil, google_expiry: nil, gmail_read: nil, gmail_write: nil, calendar_read: nil, calendar_write: nil, hubspot: nil}

    test "list_users/0 returns all users" do
      user = user_fixture()
      assert Accounts.list_users() == [user]
    end

    test "get_user!/1 returns the user with given id" do
      user = user_fixture()
      assert Accounts.get_user!(user.id) == user
    end

    test "create_user/1 with valid data creates a user" do
      valid_attrs = %{name: "some name", username: "some username", email: "some email", picture: "some picture", verified: true, google_access_token: "some google_access_token", google_refresh_token: "some google_refresh_token", google_expiry: ~U[2025-07-11 12:38:00Z], gmail_read: true, gmail_write: true, calendar_read: true, calendar_write: true, hubspot: true}

      assert {:ok, %User{} = user} = Accounts.create_user(valid_attrs)
      assert user.name == "some name"
      assert user.username == "some username"
      assert user.email == "some email"
      assert user.picture == "some picture"
      assert user.verified == true
      assert user.google_access_token == "some google_access_token"
      assert user.google_refresh_token == "some google_refresh_token"
      assert user.google_expiry == ~U[2025-07-11 12:38:00Z]
      assert user.gmail_read == true
      assert user.gmail_write == true
      assert user.calendar_read == true
      assert user.calendar_write == true
      assert user.hubspot == true
    end

    test "create_user/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Accounts.create_user(@invalid_attrs)
    end

    test "update_user/2 with valid data updates the user" do
      user = user_fixture()
      update_attrs = %{name: "some updated name", username: "some updated username", email: "some updated email", picture: "some updated picture", verified: false, google_access_token: "some updated google_access_token", google_refresh_token: "some updated google_refresh_token", google_expiry: ~U[2025-07-12 12:38:00Z], gmail_read: false, gmail_write: false, calendar_read: false, calendar_write: false, hubspot: false}

      assert {:ok, %User{} = user} = Accounts.update_user(user, update_attrs)
      assert user.name == "some updated name"
      assert user.username == "some updated username"
      assert user.email == "some updated email"
      assert user.picture == "some updated picture"
      assert user.verified == false
      assert user.google_access_token == "some updated google_access_token"
      assert user.google_refresh_token == "some updated google_refresh_token"
      assert user.google_expiry == ~U[2025-07-12 12:38:00Z]
      assert user.gmail_read == false
      assert user.gmail_write == false
      assert user.calendar_read == false
      assert user.calendar_write == false
      assert user.hubspot == false
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
