defmodule Leitor.Release do
  @moduledoc """
  Used for executing DB release tasks when run in production without Mix
  installed.
  """
  alias Leitor.Dictionary.Import

  @app :leitor

  @doc "Applies all pending migrations, raising if the repository cannot start or a migration fails."
  @spec migrate() :: :ok
  def migrate do
    load_app()

    Enum.each(repos(), fn repo ->
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end)
  end

  @doc "Rolls a repository back to the given migration version, raising on failure."
  @spec rollback(module(), non_neg_integer()) :: :ok
  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
    :ok
  end

  @doc """
  Replaces the dictionary with a kaikki.org English dump from an HTTPS URL or
  a local `.jsonl`/`.jsonl.gz` path. See `Leitor.Dictionary.Import.import/1`.
  """
  @spec import_dictionary(String.t()) :: {:ok, non_neg_integer()} | {:error, term()}
  def import_dictionary(source) do
    load_app()
    {:ok, _started} = Application.ensure_all_started(:req)
    {:ok, result, _started} = Ecto.Migrator.with_repo(Leitor.Repo, fn _repo -> Import.import(source) end)
    result
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    # Many platforms require SSL when connecting to the database
    {:ok, _started} = Application.ensure_all_started(:ssl)
    :ok = Application.ensure_loaded(@app)
  end
end
