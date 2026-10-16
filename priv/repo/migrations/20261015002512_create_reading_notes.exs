defmodule Leitor.Repo.Migrations.CreateReadingNotes do
  use Ecto.Migration

  def change do
    create table(:reading_notes, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :text_id, references(:texts, type: :binary_id, on_delete: :delete_all), null: false
      add :sentence_index, :integer, null: false
      add :quote, :text, null: false
      add :body, :text, null: false
      add :kind, :string, null: false, default: "personal"
      add :question, :text
      add :references, {:array, :integer}, null: false, default: []
      timestamps(type: :utc_datetime)
    end

    create index(:reading_notes, [:text_id, :sentence_index])
    create constraint(:reading_notes, :nonnegative_sentence_index, check: "sentence_index >= 0")
  end
end
