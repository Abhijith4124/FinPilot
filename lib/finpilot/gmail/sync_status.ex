defmodule Finpilot.Gmail.SyncStatus do
  use Ecto.Schema
  import Ecto.Changeset

  schema "gmail_sync_status" do
    field :last_history_id, :string
    field :last_sync_at, :utc_datetime
    field :sync_status, :string
    field :total_emails_processed, :integer
    field :last_error_message, :string
    field :sync_from_date, :date
    field :sync_to_date, :date
    field :user_id, :id

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(sync_status, attrs) do
    sync_status
    |> cast(attrs, [:last_history_id, :last_sync_at, :sync_status, :total_emails_processed, :last_error_message, :sync_from_date, :sync_to_date])
    |> validate_required([:last_history_id, :last_sync_at, :sync_status, :total_emails_processed, :last_error_message, :sync_from_date, :sync_to_date])
  end
end
