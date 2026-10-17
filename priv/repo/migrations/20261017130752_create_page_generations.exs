defmodule Leitor.Repo.Migrations.CreatePageGenerations do
  use Ecto.Migration

  def change do
    create table(:page_generations, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :text_id, references(:texts, type: :binary_id, on_delete: :delete_all)
      add :request, :map, null: false
      add :client_id, :string, null: false
      add :revision_id, references(:figure_artifacts, type: :binary_id, on_delete: :nilify_all)
      add :lease_id, references(:ai_reservations, type: :binary_id, on_delete: :nilify_all)
      add :expires_at, :utc_datetime, null: false
      add :status, :string, null: false
      add :stage, :string, null: false
      add :markdown, :text
      add :error, :string
      add :dismissed, :boolean, null: false, default: false
      timestamps(type: :utc_datetime)
    end

    create index(:page_generations, [:user_id, :text_id, :id])

    create constraint(:page_generations, :page_generation_status,
             check: "status IN ('running', 'ready', 'failed')"
           )
  end
end
