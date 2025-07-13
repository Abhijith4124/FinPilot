defmodule Finpilot.Repo.Migrations.CreateChatSessions do
  use Ecto.Migration

  def change do
    create table(:chat_sessions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :title, :string
      add :status, :string
      add :user_id, references(:users, on_delete: :delete_all, type: :binary_id)

      timestamps(type: :utc_datetime)
    end

    create index(:chat_sessions, [:user_id])
    create index(:chat_sessions, [:status])
  end
end
