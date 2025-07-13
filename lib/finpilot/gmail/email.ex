defmodule Finpilot.Gmail.Email do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "emails" do
    field :gmail_message_id, :string
    field :subject, :string
    field :sender, :string
    field :recipients, :string
    field :content, :string
    field :received_at, :utc_datetime
    field :thread_id, :string
    field :labels, :string
    field :embedding, Pgvector.Ecto.Vector
    field :processed_at, :utc_datetime
    
    belongs_to :user, Finpilot.Accounts.User

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(email, attrs) do
    email
    |> cast(attrs, [:gmail_message_id, :subject, :sender, :recipients, :content, :received_at, :thread_id, :labels, :embedding, :processed_at, :user_id])
    |> validate_required([:gmail_message_id, :subject, :sender, :content, :received_at, :thread_id, :user_id])
    |> unique_constraint(:gmail_message_id)
    |> foreign_key_constraint(:user_id)
  end
end
