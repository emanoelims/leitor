defmodule Leitor.Repo.Migrations.AddUserPreferences do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :preferences, :map, null: false, default: %{}
    end
  end
end
