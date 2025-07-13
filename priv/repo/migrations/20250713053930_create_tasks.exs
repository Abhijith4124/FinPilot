defmodule Finpilot.Repo.Migrations.CreateTasks do
  use Ecto.Migration

  def change do
    create table(:tasks, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :task_instruction, :text
      add :current_summary, :text
      add :next_instruction, :text
      add :is_done, :boolean, default: false, null: false
      add :context, :map
      add :user_id, references(:users, on_delete: :nothing, type: :binary_id)
      add :embedding, :vector, size: 1536

      timestamps(type: :utc_datetime)
    end

    create index(:tasks, [:user_id])
  end
end
