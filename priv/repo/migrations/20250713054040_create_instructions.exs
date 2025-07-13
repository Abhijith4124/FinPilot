defmodule Finpilot.Repo.Migrations.CreateInstructions do
  use Ecto.Migration

  def change do
    create table(:instructions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string
      add :description, :text
      add :trigger_conditions, :map
      add :actions, :map
      add :ai_prompt, :text
      add :is_active, :boolean, default: false, null: false
      add :user_id, references(:users, on_delete: :nothing, type: :binary_id)

      timestamps(type: :utc_datetime)
    end

    create index(:instructions, [:user_id])
  end
end
