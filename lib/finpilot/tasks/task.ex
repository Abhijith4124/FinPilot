defmodule Finpilot.Tasks.Task do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "tasks" do
    field :context, :map
    field :task_instruction, :string
    field :current_summary, :string
    field :next_instruction, :string
    field :is_done, :boolean, default: false
    field :embedding, Pgvector.Ecto.Vector
    belongs_to :user, Finpilot.Accounts.User

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(task, attrs) do
    task
    |> cast(attrs, [:task_instruction, :current_summary, :next_instruction, :is_done, :context, :embedding])
    |> validate_required([:task_instruction, :current_summary, :next_instruction, :is_done])
  end
end
