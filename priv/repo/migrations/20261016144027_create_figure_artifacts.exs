defmodule Leitor.Repo.Migrations.CreateFigureArtifacts do
  use Ecto.Migration

  def change do
    create table(:figure_artifacts, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :title, :text, null: false
      add :caption, :text, null: false
      add :model, :text, null: false
      add :source, :map, null: false
      add :report, :map, null: false
      add :bundle, :binary
      add :style, :text
      add :preview, :binary
      add :digest, :string
      add :status, :string, null: false
      timestamps(type: :utc_datetime)
    end

    create index(:figure_artifacts, [:user_id])
  end
end
