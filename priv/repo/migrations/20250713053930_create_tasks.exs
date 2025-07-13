defmodule Finpilot.Repo.Migrations.CreateTasks do
  use Ecto.Migration

  def change do
    create table(:tasks, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :task_instruction, :text
      add :current_stage_summary, :text
      add :next_stage_instruction, :text
      add :is_done, :boolean, default: false, null: false
      add :context, :map
      # Event-driven email processing fields
      add :thread_id, :string
      add :waiting_for_sender, :string
      add :expected_response_type, :string
      add :user_id, references(:users, on_delete: :nothing, type: :binary_id)
      add :embedding, :vector, size: 1536

      timestamps(type: :utc_datetime)
    end

    create index(:tasks, [:user_id])
  end
end
