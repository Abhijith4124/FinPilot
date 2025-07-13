defmodule Finpilot.Tasks.TaskStage do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "task_stages" do
    field :status, :string
    field :started_at, :utc_datetime
    field :stage_name, :string
    field :stage_type, :string
    field :tool_name, :string
    field :tool_params, :map
    field :tool_result, :map
    field :ai_reasoning, :string
    field :completed_at, :utc_datetime
    field :error_message, :string
    belongs_to :task, Finpilot.Tasks.Task

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(task_stage, attrs) do
    task_stage
    |> cast(attrs, [:stage_name, :stage_type, :tool_name, :tool_params, :tool_result, :ai_reasoning, :status, :started_at, :completed_at, :error_message])
    |> validate_required([:stage_name, :stage_type, :tool_name, :ai_reasoning, :status, :started_at, :completed_at, :error_message])
  end
end
