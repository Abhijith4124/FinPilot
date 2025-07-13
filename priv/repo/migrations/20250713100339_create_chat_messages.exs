defmodule Finpilot.Repo.Migrations.CreateChatMessages do
  use Ecto.Migration

  def change do
    create table(:chat_messages, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :message, :text
      add :role, :string
      add :embedding, :vector, size: 1536
      add :session_id, references(:chat_sessions, on_delete: :delete_all, type: :binary_id)
      add :user_id, references(:users, on_delete: :delete_all, type: :binary_id)

      timestamps(type: :utc_datetime)
    end

    create index(:chat_messages, [:session_id])
    create index(:chat_messages, [:user_id])
    create index(:chat_messages, [:inserted_at])
  end
end
