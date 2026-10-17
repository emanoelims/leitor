defmodule Leitor.Repo.Migrations.AddFigureLineageAndAiMeasurements do
  use Ecto.Migration

  def change do
    alter table(:figure_artifacts) do
      add :parent_id, references(:figure_artifacts, type: :binary_id, on_delete: :nilify_all)
    end

    create index(:figure_artifacts, [:user_id, :parent_id])

    alter table(:ai_reservations) do
      add :model, :string
      add :outcome, :string
      add :input_tokens, :bigint, default: 0, null: false
      add :output_tokens, :bigint, default: 0, null: false
      add :cache_read_tokens, :bigint, default: 0, null: false
      add :cache_write_tokens, :bigint, default: 0, null: false
      add :estimated_cost_micros, :bigint, default: 0, null: false
      add :measured_calls, :integer, default: 0, null: false
      add :unmeasured_calls, :integer, default: 0, null: false
    end

    create index(:ai_reservations, [:user_id, :inserted_at])
  end
end
