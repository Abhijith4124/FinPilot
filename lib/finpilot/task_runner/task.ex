defmodule Finpilot.TaskRunner.Task do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "tasks" do
    field :context, :map
    field :task_instruction, :string
    field :current_stage_summary, :string
    field :next_stage_instruction, :string
    field :is_done, :boolean, default: false
    field :embedding, Pgvector.Ecto.Vector
    belongs_to :user, Finpilot.Accounts.User
    has_many :task_stages, Finpilot.TaskRunner.TaskStage

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(task, attrs) do
    task
    |> cast(attrs, [:task_instruction, :current_stage_summary, :next_stage_instruction, :is_done, :context, :embedding])
    |> validate_required([:task_instruction, :current_stage_summary, :next_stage_instruction, :is_done])
  end
end
