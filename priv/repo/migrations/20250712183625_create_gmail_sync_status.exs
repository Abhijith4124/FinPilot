defmodule Finpilot.Repo.Migrations.CreateGmailSyncStatus do
  use Ecto.Migration

  def change do
    create table(:gmail_sync_status, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :last_history_id, :string
      add :last_sync_at, :utc_datetime
      add :sync_status, :string
      add :total_emails_processed, :integer
      add :last_error_message, :text
      add :sync_from_date, :date
      add :sync_to_date, :date
      add :user_id, references(:users, on_delete: :nothing, type: :binary_id)

      timestamps(type: :utc_datetime)
    end

    create index(:gmail_sync_status, [:user_id])
  end
end
