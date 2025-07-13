defmodule Finpilot.Tasks.Instruction do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "instructions" do
    field :name, :string
    field :description, :string
    field :trigger_conditions, :map
    field :actions, :map
    field :ai_prompt, :string
    field :is_active, :boolean, default: false
    belongs_to :user, Finpilot.Accounts.User

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(instruction, attrs) do
    instruction
    |> cast(attrs, [:name, :description, :trigger_conditions, :actions, :ai_prompt, :is_active])
    |> validate_required([:name, :description, :ai_prompt, :is_active])
  end
end
