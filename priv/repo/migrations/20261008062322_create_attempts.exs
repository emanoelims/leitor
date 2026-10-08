defmodule Leitor.Repo.Migrations.CreateAttempts do
  use Ecto.Migration

  def change do
    create table(:attempts, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :kind, :string
      add :content, :text
      add :result, :map
      add :duration, :integer
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all)

      timestamps(type: :utc_datetime)
    end

    create index(:attempts, [:user_id])
  end
end
