defmodule Leitor.Repo.Migrations.AddGuestDraftImportKeys do
  use Ecto.Migration

  def change do
    alter table(:page_marks), do: add(:import_key, :binary_id)
    create unique_index(:page_marks, [:user_id, :text_id, :import_key])
  end
end
