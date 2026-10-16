defmodule Leitor.Repo.Migrations.AddRepliesToPageMarks do
  use Ecto.Migration

  def change do
    alter table(:page_marks) do
      add :replies, :map, null: false, default: fragment("'[]'::jsonb")
    end
  end
end
