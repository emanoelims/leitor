defmodule Leitor.Repo.Migrations.CreateDictionaryCards do
  use Ecto.Migration

  # Generated dictionary cards, reused when the same selection is looked up again. No user data.
  def change do
    create table(:dictionary_cards, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :key, :string, null: false
      add :model, :string, null: false
      add :card, :map, null: false
      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:dictionary_cards, [:key])
  end
end
