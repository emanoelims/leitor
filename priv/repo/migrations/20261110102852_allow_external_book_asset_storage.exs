defmodule Leitor.Repo.Migrations.AllowExternalBookAssetStorage do
  use Ecto.Migration

  # An image's bytes live either in the row (existing imports, and environments without object
  # storage) or in an object named by `storage_key`; never both and never neither.
  def change do
    alter table(:book_assets) do
      modify :data, :binary, null: true, from: {:binary, null: false}
      add :storage_key, :string
    end

    create constraint(:book_assets, :book_assets_one_location,
             check:
               "(data IS NOT NULL AND storage_key IS NULL) OR (data IS NULL AND storage_key IS NOT NULL)"
           )
  end
end
