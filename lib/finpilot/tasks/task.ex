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
    belongs_to :user, Finpilot.Accounts.User
    belongs_to :chat_session, Finpilot.ChatSessions.ChatSession, foreign_key: :session_id

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(task, attrs) do
    task
    |> cast(attrs, [:task_instruction, :current_summary, :next_instruction, :is_done, :context, :user_id, :session_id])
    |> validate_required([:task_instruction, :current_summary, :next_instruction, :is_done, :user_id, :context])
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:session_id)
  end
end
