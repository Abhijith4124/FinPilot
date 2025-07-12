defmodule Finpilot.Accounts.User do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "users" do
    field :name, :string
    field :username, :string
    field :email, :string
    field :picture, :string
    field :verified, :boolean, default: false
    field :google_access_token, :string
    field :google_refresh_token, :string
    field :google_expiry, :utc_datetime
    field :gmail_read, :boolean, default: false
    field :gmail_write, :boolean, default: false
    field :calendar_read, :boolean, default: false
    field :calendar_write, :boolean, default: false
    field :hubspot, :boolean, default: false

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(user, attrs) do
    user
    |> cast(attrs, [:username, :email, :name, :picture, :verified, :google_access_token, :google_refresh_token, :google_expiry, :gmail_read, :gmail_write, :calendar_read, :calendar_write, :hubspot])
    |> validate_required([:email])
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+$/, message: "must have the @ sign and no spaces")
    |> put_username_from_email()
    |> validate_length(:username, min: 1, max: 160)
    |> unique_constraint(:email)
    |> unique_constraint(:username)
  end

  # Private function to extract username from email
  defp put_username_from_email(changeset) do
    case get_change(changeset, :email) do
      nil -> changeset
      email when is_binary(email) ->
        username = email |> String.split("@") |> List.first()
        put_change(changeset, :username, username)
      _ -> changeset
    end
  end

  @doc """
  Returns a map of Google OAuth tokens for the user.
  """
  def google_tokens(%__MODULE__{} = user) do
    %{
      access_token: user.google_access_token,
      refresh_token: user.google_refresh_token,
      expiry: user.google_expiry
    }
  end

  @doc """
  Returns a map of connection permissions for the user.
  """
  def connection_permissions(%__MODULE__{} = user) do
    %{
      gmail_read: user.gmail_read,
      gmail_write: user.gmail_write,
      calendar_read: user.calendar_read,
      calendar_write: user.calendar_write,
      hubspot: user.hubspot
    }
  end

  @doc """
  Checks if the user has valid Google OAuth tokens.
  """
  def has_valid_google_tokens?(%__MODULE__{} = user) do
    not is_nil(user.google_access_token) and
      not is_nil(user.google_refresh_token) and
      (is_nil(user.google_expiry) or DateTime.compare(user.google_expiry, DateTime.utc_now()) == :gt)
  end
end
