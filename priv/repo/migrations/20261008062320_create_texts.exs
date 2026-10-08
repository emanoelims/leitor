defmodule Leitor.Repo.Migrations.CreateTexts do
  use Ecto.Migration

  def change do
    create table(:texts, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :title, :string
      add :body, :text
      add :position, :integer
      add :source, :string
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all)

      timestamps(type: :utc_datetime)
    end

    create index(:texts, [:user_id])
  end
end
