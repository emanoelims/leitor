defmodule Leitor.Repo.Migrations.CreateBookAssets do
  use Ecto.Migration

  def change do
    create table(:book_assets, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :book_id, references(:books, type: :binary_id, on_delete: :delete_all), null: false
      add :content_type, :string, null: false
      add :byte_size, :integer, null: false
      add :digest, :binary, null: false
      add :data, :binary, null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:book_assets, [:book_id])
  end
end
