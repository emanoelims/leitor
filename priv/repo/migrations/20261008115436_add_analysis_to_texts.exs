defmodule Leitor.Repo.Migrations.AddAnalysisToTexts do
  use Ecto.Migration

  def change do
    alter table(:texts) do
      add :analysis, :map, default: %{}, null: false
    end
  end
end
