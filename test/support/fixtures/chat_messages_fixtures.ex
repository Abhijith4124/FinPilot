defmodule Finpilot.ChatMessagesFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Finpilot.ChatMessages` context.
  """

  @doc """
  Generate a chat_message.
  """
  def chat_message_fixture(attrs \\ %{}) do
    {:ok, chat_message} =
      attrs
      |> Enum.into(%{
        message: "some message",
        role: "some role"
      })
      |> Finpilot.ChatMessages.create_chat_message()

    chat_message
  end
end
