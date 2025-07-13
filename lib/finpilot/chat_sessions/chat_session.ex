defmodule Finpilot.ChatSessions.ChatSession do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "chat_sessions" do
    field :status, :string
    field :title, :string
    belongs_to :user, Finpilot.Accounts.User
    has_many :chat_messages, Finpilot.ChatMessages.ChatMessage, foreign_key: :session_id

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(chat_session, attrs) do
    chat_session
    |> cast(attrs, [:title, :status, :user_id])
    |> validate_required([:status, :user_id])
    |> validate_inclusion(:status, ["active", "archived", "deleted"])
  end
end
