defmodule Leitor.Repo.Migrations.AddBookIdToTexts do
  use Ecto.Migration

  def change do
    alter table(:texts) do
      add :book_id, references(:books, type: :binary_id, on_delete: :delete_all)
    end

    create index(:texts, [:book_id, :position])
  end
end
