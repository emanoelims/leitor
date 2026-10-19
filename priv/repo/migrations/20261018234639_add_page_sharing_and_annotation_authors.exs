defmodule Leitor.Repo.Migrations.AddPageSharingAndAnnotationAuthors do
  use Ecto.Migration

  def up do
    alter table(:page_marks) do
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all)
    end

    execute "UPDATE page_marks SET user_id = texts.user_id FROM texts WHERE texts.id = page_marks.text_id"
    alter table(:page_marks), do: modify(:user_id, :binary_id, null: false)
    create index(:page_marks, [:user_id, :text_id])

    create table(:page_shares, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :text_id, references(:texts, type: :binary_id, on_delete: :delete_all), null: false
      add :token, :string, null: false
      add :link_role, :string, null: false, default: "disabled"
      timestamps(type: :utc_datetime)
    end

    create unique_index(:page_shares, [:text_id])
    create unique_index(:page_shares, [:token])

    create constraint(:page_shares, :valid_link_role,
             check: "link_role IN ('disabled', 'view', 'comment')"
           )

    create table(:page_collaborators, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :share_id, references(:page_shares, type: :binary_id, on_delete: :delete_all),
        null: false

      add :email, :citext, null: false
      add :role, :string, null: false
      timestamps(type: :utc_datetime)
    end

    create unique_index(:page_collaborators, [:share_id, :email])

    create constraint(:page_collaborators, :valid_collaborator_role,
             check: "role IN ('view', 'comment')"
           )

    create table(:page_comments, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :share_id, references(:page_shares, type: :binary_id, on_delete: :delete_all),
        null: false

      add :user_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :visitor_id, :binary_id, null: false
      add :author_name, :string, null: false
      add :body, :text, null: false
      add :quote, :text, null: false
      add :from_offset, :integer, null: false
      add :to_offset, :integer, null: false
      add :block_index, :integer, null: false
      add :parent_id, references(:page_comments, type: :binary_id, on_delete: :nilify_all)
      add :deleted_at, :utc_datetime
      timestamps(type: :utc_datetime)
    end

    create index(:page_comments, [:share_id, :inserted_at])
    create index(:page_comments, [:share_id, :visitor_id, :inserted_at])
  end

  def down do
    drop table(:page_comments)
    drop table(:page_collaborators)
    drop table(:page_shares)
    alter table(:page_marks), do: remove(:user_id)
  end
end
