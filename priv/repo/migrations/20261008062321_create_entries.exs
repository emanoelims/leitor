defmodule Leitor.Repo.Migrations.CreateEntries do
  use Ecto.Migration

  def change do
    create table(:entries, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :term, :string
      add :meaning, :string
      add :category, :string
      add :context, :text
      add :status, :string
      add :interval, :integer
      add :due_at, :utc_datetime
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all)

      timestamps(type: :utc_datetime)
    end

    create unique_index(:entries, [:user_id, :term])
    create index(:entries, [:user_id, :status, :due_at])
  end
end
