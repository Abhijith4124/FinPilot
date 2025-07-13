defmodule Finpilot.Repo.Migrations.CreateEmails do
  use Ecto.Migration

  def change do
    create table(:emails, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :gmail_message_id, :string
      add :subject, :string
      add :sender, :string
      add :recipients, :text
      add :content, :text
      add :received_at, :utc_datetime
      add :thread_id, :string
      add :labels, :text
      add :embedding, :vector, size: 1536
      add :processed_at, :utc_datetime
      add :user_id, references(:users, on_delete: :nothing, type: :binary_id)

      timestamps(type: :utc_datetime)
    end

    create index(:emails, [:user_id])
    create unique_index(:emails, [:gmail_message_id])
    create index(:emails, [:thread_id])
    create index(:emails, [:received_at])
  end
end
