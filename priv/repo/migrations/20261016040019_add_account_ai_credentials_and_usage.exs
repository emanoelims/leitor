defmodule Leitor.Repo.Migrations.AddAccountAiCredentialsAndUsage do
  use Ecto.Migration

  def change do
    create table(:ai_credentials, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :provider, :string, null: false
      add :encrypted_key, :binary, null: false
      add :hint, :string, null: false
      timestamps(type: :utc_datetime)
    end

    create unique_index(:ai_credentials, [:user_id, :provider])

    create table(:ai_usage_buckets, primary_key: false) do
      add :key, :string, primary_key: true
      add :used, :integer, default: 0, null: false
      add :personal_used, :integer, default: 0, null: false
      add :last_started_at, :utc_datetime
    end

    create constraint(:ai_usage_buckets, :nonnegative_ai_credits,
             check: "used >= 0 AND personal_used >= 0"
           )

    create table(:ai_reservations, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :operation, :string, null: false
      add :mode, :string, null: false
      add :credits, :integer, null: false
      add :expires_at, :utc_datetime, null: false
      add :finished_at, :utc_datetime
      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:ai_reservations, [:user_id, :expires_at], where: "finished_at IS NULL")
    create index(:ai_reservations, [:expires_at], where: "finished_at IS NULL")
  end
end
