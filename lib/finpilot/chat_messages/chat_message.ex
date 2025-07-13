defmodule Finpilot.ChatMessages.ChatMessage do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "chat_messages" do
    field :message, :string
    field :role, :string
    field :embedding, Pgvector.Ecto.Vector
    belongs_to :session, Finpilot.ChatSessions.ChatSession
    belongs_to :user, Finpilot.Accounts.User

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(chat_message, attrs) do
    chat_message
    |> cast(attrs, [:message, :role, :session_id, :user_id, :embedding])
    |> validate_required([:message, :role, :session_id, :user_id])
    |> validate_inclusion(:role, ["user", "assistant", "system"])
  end
end
