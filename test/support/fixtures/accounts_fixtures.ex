defmodule Finpilot.AccountsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Finpilot.Accounts` context.
  """

  @doc """
  Generate a user.
  """
  def user_fixture(attrs \\ %{}) do
    unique_id = System.unique_integer([:positive])
    
    {:ok, user} =
      attrs
      |> Enum.into(%{
        calendar_read: false,
        calendar_write: false,
        email: "user#{unique_id}@example.com",
        gmail_read: false,
        gmail_write: false,
        google_access_token: nil,
        google_expiry: nil,
        google_refresh_token: nil,
        hubspot: false,
        name: "Test User #{unique_id}",
        picture: nil,
        verified: false
      })
      |> Finpilot.Accounts.create_user()

    user
  end
end
