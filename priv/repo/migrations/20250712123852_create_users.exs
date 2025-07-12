defmodule Finpilot.Repo.Migrations.CreateUsers do
  use Ecto.Migration

  def change do
    create table(:users, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :username, :string
      add :email, :string
      add :name, :string
      add :picture, :string
      add :verified, :boolean, default: false, null: false
      add :google_access_token, :string
      add :google_refresh_token, :string
      add :google_expiry, :utc_datetime
      add :gmail_read, :boolean, default: false, null: false
      add :gmail_write, :boolean, default: false, null: false
      add :calendar_read, :boolean, default: false, null: false
      add :calendar_write, :boolean, default: false, null: false
      add :hubspot, :boolean, default: false, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:users, [:email])
    create unique_index(:users, [:username])
  end
end
