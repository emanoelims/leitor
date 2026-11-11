defmodule Leitor.Repo.Migrations.CreateBooks do
  use Ecto.Migration

  def change do
    create table(:books, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :title, :string, null: false
      add :author, :string
      add :language, :string
      add :identifier, :string
      add :toc, :map, null: false, default: %{"entries" => []}
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :last_text_id, references(:texts, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create index(:books, [:user_id])
  end
end
