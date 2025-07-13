defmodule Finpilot.Repo.Migrations.CreateTaskStages do
  use Ecto.Migration

  def change do
    create table(:task_stages, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :stage_name, :string
      add :stage_type, :string
      add :tool_name, :string
      add :tool_params, :map
      add :tool_result, :map
      add :ai_reasoning, :text
      add :status, :string
      add :started_at, :utc_datetime
      add :completed_at, :utc_datetime
      add :error_message, :text
      add :task_id, references(:tasks, on_delete: :nothing, type: :binary_id)

      timestamps(type: :utc_datetime)
    end

    create index(:task_stages, [:task_id])
  end
end
