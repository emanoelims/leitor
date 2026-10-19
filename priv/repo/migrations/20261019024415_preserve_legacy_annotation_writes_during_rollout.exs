defmodule Leitor.Repo.Migrations.PreserveLegacyAnnotationWritesDuringRollout do
  use Ecto.Migration

  def up do
    execute """
    CREATE FUNCTION public.assign_legacy_page_mark_author() RETURNS trigger
    LANGUAGE plpgsql AS $$
    BEGIN
      SELECT user_id INTO NEW.user_id FROM public.texts WHERE id = NEW.text_id;
      RETURN NEW;
    END;
    $$
    """

    execute """
    CREATE TRIGGER assign_legacy_page_mark_author
    BEFORE INSERT ON page_marks
    FOR EACH ROW WHEN (NEW.user_id IS NULL)
    EXECUTE FUNCTION public.assign_legacy_page_mark_author()
    """

    execute "UPDATE page_marks SET user_id = texts.user_id FROM texts WHERE texts.id = page_marks.text_id AND page_marks.user_id IS NULL"
    execute "ALTER TABLE page_marks ALTER COLUMN user_id SET NOT NULL"
  end

  def down do
    execute "ALTER TABLE page_marks ALTER COLUMN user_id DROP NOT NULL"
    execute "DROP TRIGGER assign_legacy_page_mark_author ON page_marks"
    execute "DROP FUNCTION public.assign_legacy_page_mark_author()"
  end
end
