defmodule Finpilot.ChatSessionsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Finpilot.ChatSessions` context.
  """

  @doc """
  Generate a chat_session.
  """
  def chat_session_fixture(attrs \\ %{}) do
    {:ok, chat_session} =
      attrs
      |> Enum.into(%{
        status: "some status",
        title: "some title"
      })
      |> Finpilot.ChatSessions.create_chat_session()

    chat_session
  end
end
