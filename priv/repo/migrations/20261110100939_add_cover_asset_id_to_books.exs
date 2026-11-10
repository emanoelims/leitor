defmodule Leitor.Repo.Migrations.AddCoverAssetIdToBooks do
  use Ecto.Migration

  # Not a foreign key: assets only disappear together with their book, and inserting
  # the book before its assets would otherwise need a deferred constraint.
  def change do
    alter table(:books) do
      add :cover_asset_id, :binary_id
    end
  end
end
