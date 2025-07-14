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
    field :attachments, :map
    
    belongs_to :user, Finpilot.Accounts.User

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(email, attrs) do
    email
    |> cast(attrs, [:gmail_message_id, :subject, :sender, :recipients, :content, :received_at, :thread_id, :labels, :embedding, :processed_at, :attachments, :user_id])
    |> validate_required([:gmail_message_id, :subject, :sender, :content, :received_at, :thread_id, :user_id])
    |> validate_recipients()
    |> unique_constraint(:gmail_message_id)
    |> foreign_key_constraint(:user_id)
  end

  defp validate_recipients(changeset) do
    validate_change(changeset, :recipients, fn :recipients, recipients ->
      case Jason.decode(recipients) do
        {:ok, %{"to" => to_list}} when is_list(to_list) -> []
        _ -> [recipients: "must be valid JSON with recipient lists"]
      end
    end)
  end
end
