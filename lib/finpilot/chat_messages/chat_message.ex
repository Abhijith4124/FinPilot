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
    |> maybe_generate_embedding()
  end

  # Automatically generate embeddings for user and assistant messages
  defp maybe_generate_embedding(%Ecto.Changeset{valid?: true} = changeset) do
    role = get_change(changeset, :role) || get_field(changeset, :role)
    message = get_change(changeset, :message) || get_field(changeset, :message)
    existing_embedding = get_change(changeset, :embedding) || get_field(changeset, :embedding)

    # Only generate embedding if:
    # 1. Role is user or assistant
    # 2. Message is present and not empty
    # 3. No embedding is already provided
    if role in ["user", "assistant"] and is_binary(message) and message != "" and is_nil(existing_embedding) do
      case Finpilot.Services.OpenAI.generate_embedding_small(message) do
        {:ok, embedding} ->
          put_change(changeset, :embedding, embedding)
        {:error, _reason} ->
          # Don't fail the changeset if embedding generation fails
          # Log the error but continue without embedding
          changeset
      end
    else
      changeset
    end
  end

  defp maybe_generate_embedding(changeset), do: changeset
end
