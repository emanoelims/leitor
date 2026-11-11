defmodule Leitor.Repo.Migrations.AddCardToPageMarks do
  use Ecto.Migration

  def change do
    alter table(:page_marks) do
      add :card, :map
    end
  end
end
