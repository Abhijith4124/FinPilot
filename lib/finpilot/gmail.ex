defmodule Finpilot.Gmail do
  @moduledoc """
  The Gmail context.
  """

  import Ecto.Query, warn: false
  alias Finpilot.Repo

  alias Finpilot.Gmail.SyncStatus

  @doc """
  Returns the list of gmail_sync_status.

  ## Examples

      iex> list_gmail_sync_status()
      [%SyncStatus{}, ...]

  """
  def list_gmail_sync_status do
    Repo.all(SyncStatus)
  end

  @doc """
  Gets a single sync_status.

  Raises `Ecto.NoResultsError` if the Sync status does not exist.

  ## Examples

      iex> get_sync_status!(123)
      %SyncStatus{}

      iex> get_sync_status!(456)
      ** (Ecto.NoResultsError)

  """
  def get_sync_status!(id), do: Repo.get!(SyncStatus, id)

  @doc """
  Gets a sync_status by user_id.

  ## Examples

      iex> get_sync_status_by_user_id("user_123")
      %SyncStatus{}

      iex> get_sync_status_by_user_id("nonexistent")
      nil

  """
  def get_sync_status_by_user_id(user_id) do
    SyncStatus
    |> where([s], s.user_id == ^user_id)
    |> Repo.one()
  end

  @doc """
  Creates a sync_status.

  ## Examples

      iex> create_sync_status(%{field: value})
      {:ok, %SyncStatus{}}

      iex> create_sync_status(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_sync_status(attrs \\ %{}) do
    %SyncStatus{}
    |> SyncStatus.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a sync_status.

  ## Examples

      iex> update_sync_status(sync_status, %{field: new_value})
      {:ok, %SyncStatus{}}

      iex> update_sync_status(sync_status, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_sync_status(%SyncStatus{} = sync_status, attrs) do
    sync_status
    |> SyncStatus.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a sync_status.

  ## Examples

      iex> delete_sync_status(sync_status)
      {:ok, %SyncStatus{}}

      iex> delete_sync_status(sync_status)
      {:error, %Ecto.Changeset{}}

  """
  def delete_sync_status(%SyncStatus{} = sync_status) do
    Repo.delete(sync_status)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking sync_status changes.

  ## Examples

      iex> change_sync_status(sync_status)
      %Ecto.Changeset{data: %SyncStatus{}}

  """
  def change_sync_status(%SyncStatus{} = sync_status, attrs \\ %{}) do
    SyncStatus.changeset(sync_status, attrs)
  end

  alias Finpilot.Gmail.Email

  @doc """
  Returns the list of emails.

  ## Examples

      iex> list_emails()
      [%Email{}, ...]

  """
  def list_emails do
    Repo.all(Email)
  end

  @doc """
  Gets a single email.

  Raises `Ecto.NoResultsError` if the Email does not exist.

  ## Examples

      iex> get_email!(123)
      %Email{}

      iex> get_email!(456)
      ** (Ecto.NoResultsError)

  """
  def get_email!(id), do: Repo.get!(Email, id)

  @doc """
  Gets an email by Gmail message ID.

  ## Examples

      iex> get_email_by_gmail_message_id("gmail_123")
      %Email{}

      iex> get_email_by_gmail_message_id("nonexistent")
      nil

  """
  def get_email_by_gmail_message_id(gmail_message_id) do
    Email
    |> where([e], e.gmail_message_id == ^gmail_message_id)
    |> Repo.one()
  end

  @doc """
  Creates a email.

  ## Examples

      iex> create_email(%{field: value})
      {:ok, %Email{}}

      iex> create_email(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_email(attrs \\ %{}) do
    %Email{}
    |> Email.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a email.

  ## Examples

      iex> update_email(email, %{field: new_value})
      {:ok, %Email{}}

      iex> update_email(email, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_email(%Email{} = email, attrs) do
    email
    |> Email.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a email.

  ## Examples

      iex> delete_email(email)
      {:ok, %Email{}}

      iex> delete_email(email)
      {:error, %Ecto.Changeset{}}

  """
  def delete_email(%Email{} = email) do
    Repo.delete(email)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking email changes.

  ## Examples

      iex> change_email(email)
      %Ecto.Changeset{data: %Email{}}

  """
  def change_email(%Email{} = email, attrs \\ %{}) do
    Email.changeset(email, attrs)
  end

  @doc """
  Gets emails sent to a specific email address.

  ## Examples

      iex> emails_sent_to("user_123", "john@example.com")
      [%Email{}, ...]

  """
  def emails_sent_to(user_id, email_address) do
    from(e in Email,
      where: e.user_id == ^user_id,
      where: fragment("? ->> 'to' ILIKE ?", e.recipients, ^"%#{email_address}%")
    )
    |> Repo.all()
  end

  @doc """
  Gets emails with a specific recipient in CC.

  ## Examples

      iex> emails_with_cc("user_123", "jane@example.com")
      [%Email{}, ...]

  """
  def emails_with_cc(user_id, email_address) do
    from(e in Email,
      where: e.user_id == ^user_id,
      where: fragment("? ->> 'cc' ILIKE ?", e.recipients, ^"%#{email_address}%")
    )
    |> Repo.all()
  end

  @doc """
  Gets emails involving a specific email address (to, cc, or bcc).

  ## Examples

      iex> emails_involving("user_123", "contact@example.com")
      [%Email{}, ...]

  """
  def emails_involving(user_id, email_address) do
    from(e in Email,
      where: e.user_id == ^user_id,
      where: fragment("? ILIKE ?", e.recipients, ^"%#{email_address}%")
    )
    |> Repo.all()
  end
end
