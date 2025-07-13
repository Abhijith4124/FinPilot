defmodule Finpilot.ChatMessages do
  @moduledoc """
  The ChatMessages context.
  """

  import Ecto.Query, warn: false
  alias Finpilot.Repo
  alias Phoenix.PubSub

  alias Finpilot.ChatMessages.ChatMessage

  @doc """
  Returns the list of chat_messages.

  ## Examples

      iex> list_chat_messages()
      [%ChatMessage{}, ...]

  """
  def list_chat_messages do
    Repo.all(ChatMessage)
  end

  @doc """
  Returns the list of chat messages for a specific session, ordered chronologically.

  ## Examples

      iex> list_messages_by_session(session_id)
      [%ChatMessage{}, ...]

  """
  def list_messages_by_session(session_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)
    offset = Keyword.get(opts, :offset, 0)

    ChatMessage
    |> where([cm], cm.session_id == ^session_id)
    |> order_by([cm], asc: cm.inserted_at)
    |> limit(^limit)
    |> offset(^offset)
    |> Repo.all()
  end

  @doc """
  Creates a user message in a chat session.

  ## Examples

      iex> create_user_message(session_id, user_id, "Hello!")
      {:ok, %ChatMessage{}}

  """
  def create_user_message(session_id, user_id, message) do
    attrs = %{
      session_id: session_id,
      user_id: user_id,
      message: message,
      role: "user"
    }
    
    create_chat_message(attrs)
  end

  @doc """
  Creates an assistant message in a chat session.

  ## Examples

      iex> create_assistant_message(session_id, user_id, "Hello! How can I help?")
      {:ok, %ChatMessage{}}

  """
  def create_assistant_message(session_id, user_id, message) do
    attrs = %{
      session_id: session_id,
      user_id: user_id,
      message: message,
      role: "assistant"
    }
    
    create_chat_message(attrs)
  end

  @doc """
  Creates a system message in a chat session.

  ## Examples

      iex> create_system_message(session_id, user_id, "Task completed successfully")
      {:ok, %ChatMessage{}}

  """
  def create_system_message(session_id, user_id, message) do
    attrs = %{
      session_id: session_id,
      user_id: user_id,
      message: message,
      role: "system"
    }
    
    create_chat_message(attrs)
  end

  @doc """
  Gets the conversation history for a session in OpenAI format.

  ## Examples

      iex> get_conversation_history(session_id)
      [%{"role" => "user", "content" => "Hello!"}, ...]

  """
  def get_conversation_history(session_id) do
    session_id
    |> list_messages_by_session()
    |> Enum.map(fn message ->
      %{
        "role" => message.role,
        "content" => message.message
      }
    end)
  end

  @doc """
  Gets a single chat_message.

  Raises `Ecto.NoResultsError` if the Chat message does not exist.

  ## Examples

      iex> get_chat_message!(123)
      %ChatMessage{}

      iex> get_chat_message!(456)
      ** (Ecto.NoResultsError)

  """
  def get_chat_message!(id), do: Repo.get!(ChatMessage, id)

  @doc """
  Creates a chat_message.

  ## Examples

      iex> create_chat_message(%{field: value})
      {:ok, %ChatMessage{}}

      iex> create_chat_message(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_chat_message(attrs \\ %{}) do
    case %ChatMessage{}
         |> ChatMessage.changeset(attrs)
         |> Repo.insert() do
      {:ok, message} = result ->
        # Broadcast the new message to all subscribers of this chat session
        PubSub.broadcast(
          Finpilot.PubSub,
          "chat_session:#{message.session_id}",
          {:new_message, message}
        )
        result
      error ->
        error
    end
  end

  @doc """
  Updates a chat_message.

  ## Examples

      iex> update_chat_message(chat_message, %{field: new_value})
      {:ok, %ChatMessage{}}

      iex> update_chat_message(chat_message, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_chat_message(%ChatMessage{} = chat_message, attrs) do
    chat_message
    |> ChatMessage.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a chat_message.

  ## Examples

      iex> delete_chat_message(chat_message)
      {:ok, %ChatMessage{}}

      iex> delete_chat_message(chat_message)
      {:error, %Ecto.Changeset{}}

  """
  def delete_chat_message(%ChatMessage{} = chat_message) do
    Repo.delete(chat_message)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking chat_message changes.

  ## Examples

      iex> change_chat_message(chat_message)
      %Ecto.Changeset{data: %ChatMessage{}}

  """
  def change_chat_message(%ChatMessage{} = chat_message, attrs \\ %{}) do
    ChatMessage.changeset(chat_message, attrs)
  end
end
