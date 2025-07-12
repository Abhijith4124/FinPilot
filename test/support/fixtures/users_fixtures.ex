defmodule Finpilot.UsersFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Finpilot.Users` context.
  """

  @doc """
  Generate a user.
  """
  def user_fixture(attrs \\ %{}) do
    {:ok, user} =
      attrs
      |> Enum.into(%{
        email: "some email",
        profile_image: "some profile_image",
        username: "some username"
      })
      |> Finpilot.Users.create_user()

    user
  end
end
