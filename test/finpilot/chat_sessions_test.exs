defmodule Finpilot.ChatSessionsTest do
  use Finpilot.DataCase

  alias Finpilot.ChatSessions

  describe "chat_sessions" do
    alias Finpilot.ChatSessions.ChatSession

    import Finpilot.ChatSessionsFixtures

    @invalid_attrs %{status: nil, title: nil}

    test "list_chat_sessions/0 returns all chat_sessions" do
      chat_session = chat_session_fixture()
      assert ChatSessions.list_chat_sessions() == [chat_session]
    end

    test "get_chat_session!/1 returns the chat_session with given id" do
      chat_session = chat_session_fixture()
      assert ChatSessions.get_chat_session!(chat_session.id) == chat_session
    end

    test "create_chat_session/1 with valid data creates a chat_session" do
      valid_attrs = %{status: "some status", title: "some title"}

      assert {:ok, %ChatSession{} = chat_session} = ChatSessions.create_chat_session(valid_attrs)
      assert chat_session.status == "some status"
      assert chat_session.title == "some title"
    end

    test "create_chat_session/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = ChatSessions.create_chat_session(@invalid_attrs)
    end

    test "update_chat_session/2 with valid data updates the chat_session" do
      chat_session = chat_session_fixture()
      update_attrs = %{status: "some updated status", title: "some updated title"}

      assert {:ok, %ChatSession{} = chat_session} = ChatSessions.update_chat_session(chat_session, update_attrs)
      assert chat_session.status == "some updated status"
      assert chat_session.title == "some updated title"
    end

    test "update_chat_session/2 with invalid data returns error changeset" do
      chat_session = chat_session_fixture()
      assert {:error, %Ecto.Changeset{}} = ChatSessions.update_chat_session(chat_session, @invalid_attrs)
      assert chat_session == ChatSessions.get_chat_session!(chat_session.id)
    end

    test "delete_chat_session/1 deletes the chat_session" do
      chat_session = chat_session_fixture()
      assert {:ok, %ChatSession{}} = ChatSessions.delete_chat_session(chat_session)
      assert_raise Ecto.NoResultsError, fn -> ChatSessions.get_chat_session!(chat_session.id) end
    end

    test "change_chat_session/1 returns a chat_session changeset" do
      chat_session = chat_session_fixture()
      assert %Ecto.Changeset{} = ChatSessions.change_chat_session(chat_session)
    end
  end
end
