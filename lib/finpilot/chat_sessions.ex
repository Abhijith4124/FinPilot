defmodule Finpilot.ChatSessions do
  @moduledoc """
  The ChatSessions context.
  """

  import Ecto.Query, warn: false
  alias Finpilot.Repo

  alias Finpilot.ChatSessions.ChatSession

  @doc """
  Returns the list of chat_sessions.

  ## Examples

      iex> list_chat_sessions()
      [%ChatSession{}, ...]

  """
  def list_chat_sessions do
    Repo.all(ChatSession)
  end

  @doc """
  Returns the list of chat sessions for a specific user, ordered by most recent.

  ## Examples

      iex> list_chat_sessions_by_user(user_id)
      [%ChatSession{}, ...]

  """
  def list_chat_sessions_by_user(user_id, opts \\ []) do
    status = Keyword.get(opts, :status, "active")
    limit = Keyword.get(opts, :limit, 50)

    ChatSession
    |> where([cs], cs.user_id == ^user_id)
    |> where([cs], cs.status == ^status)
    |> order_by([cs], desc: cs.updated_at)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc """
  Creates a new chat session for a user.

  ## Examples

      iex> create_user_chat_session(user_id, "New Chat")
      {:ok, %ChatSession{}}

  """
  def create_user_chat_session(user_id, title \\ nil) do
    attrs = %{
      user_id: user_id,
      status: "active",
      title: title
    }
    
    create_chat_session(attrs)
  end

  @doc """
  Archives a chat session.

  ## Examples

      iex> archive_chat_session(chat_session)
      {:ok, %ChatSession{}}

  """
  def archive_chat_session(%ChatSession{} = chat_session) do
    update_chat_session(chat_session, %{status: "archived"})
  end

  @doc """
  Gets a single chat_session.

  Returns {:ok, chat_session} if found, {:error, :not_found} otherwise.

  ## Examples

      iex> get_chat_session(123)
      {:ok, %ChatSession{}}

      iex> get_chat_session(456)
      {:error, :not_found}

  """
  def get_chat_session(id) do
    case Repo.get(ChatSession, id) do
      nil -> {:error, :not_found}
      chat_session -> {:ok, chat_session}
    end
  end

  @doc """
  Gets a single chat_session.

  Raises `Ecto.NoResultsError` if the Chat session does not exist.

  ## Examples

      iex> get_chat_session!(123)
      %ChatSession{}

      iex> get_chat_session!(456)
      ** (Ecto.NoResultsError)

  """
  def get_chat_session!(id), do: Repo.get!(ChatSession, id)

  @doc """
  Creates a chat_session.

  ## Examples

      iex> create_chat_session(%{field: value})
      {:ok, %ChatSession{}}

      iex> create_chat_session(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_chat_session(attrs \\ %{}) do
    %ChatSession{}
    |> ChatSession.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a chat_session.

  ## Examples

      iex> update_chat_session(chat_session, %{field: new_value})
      {:ok, %ChatSession{}}

      iex> update_chat_session(chat_session, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_chat_session(%ChatSession{} = chat_session, attrs) do
    chat_session
    |> ChatSession.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a chat_session.

  ## Examples

      iex> delete_chat_session(chat_session)
      {:ok, %ChatSession{}}

      iex> delete_chat_session(chat_session)
      {:error, %Ecto.Changeset{}}

  """
  def delete_chat_session(%ChatSession{} = chat_session) do
    Repo.delete(chat_session)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking chat_session changes.

  ## Examples

      iex> change_chat_session(chat_session)
      %Ecto.Changeset{data: %ChatSession{}}

  """
  def change_chat_session(%ChatSession{} = chat_session, attrs \\ %{}) do
    ChatSession.changeset(chat_session, attrs)
  end
end
