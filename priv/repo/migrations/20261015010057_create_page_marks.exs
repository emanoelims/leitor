defmodule Leitor.Repo.Migrations.CreatePageMarks do
  use Ecto.Migration

  def change do
    create table(:page_marks, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :text_id, references(:texts, type: :binary_id, on_delete: :delete_all), null: false
      add :from_offset, :integer, null: false
      add :to_offset, :integer, null: false
      add :block_index, :integer, null: false
      add :quote, :text, null: false
      add :kind, :string, null: false
      add :color, :string, null: false, default: "yellow"
      add :body, :text, null: false, default: ""
      add :meaning, :text, null: false, default: ""
      add :category, :string, null: false, default: "word"
      add :question, :text
      timestamps(type: :utc_datetime)
    end

    create index(:page_marks, [:text_id, :from_offset])

    create constraint(:page_marks, :valid_offsets,
             check: "from_offset >= 0 AND to_offset > from_offset AND block_index >= 0"
           )
  end
end
