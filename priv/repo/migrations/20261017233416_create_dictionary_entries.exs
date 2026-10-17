defmodule Leitor.Repo.Migrations.CreateDictionaryEntries do
  use Ecto.Migration

  # Shared reference data imported from Wiktextract (kaikki.org); not owned by users.
  def change do
    create table(:dictionary_entries) do
      add :word, :text, null: false
      add :key, :text, null: false
      add :part_of_speech, :text, null: false
      add :ipa, :text
      add :forms, {:array, :text}, null: false, default: []
      add :form_of, {:array, :text}, null: false, default: []
      add :senses, {:array, :map}, null: false, default: []
      add :translations, {:array, :map}, null: false, default: []
    end

    create index(:dictionary_entries, [:key])
  end
end
