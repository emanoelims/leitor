defmodule Mix.Tasks.Leitor.Dictionary.Import do
  @shortdoc "Imports the kaikki.org English dictionary"
  @moduledoc """
  Replaces the dictionary with a kaikki.org English Wiktextract dump.

      $ mix leitor.dictionary.import https://kaikki.org/dictionary/English/kaikki.org-dictionary-English.jsonl.gz
      $ mix leitor.dictionary.import path/to/kaikki.org-dictionary-English.jsonl.gz

  Accepts an HTTPS URL or a local `.jsonl` or `.jsonl.gz` file. The import
  replaces every entry and takes a few minutes. In a release, use
  `Leitor.Release.import_dictionary/1`.
  """
  use Mix.Task

  alias Leitor.Dictionary.Import

  @requirements ["app.start"]

  @impl Mix.Task
  def run([source]) do
    case :timer.tc(fn -> Import.import(source) end) do
      {microseconds, {:ok, count}} ->
        Mix.shell().info("Imported #{count} dictionary entries in #{div(microseconds, 1_000_000)}s.")

      {_microseconds, {:error, reason}} ->
        Mix.raise("Dictionary import failed: #{inspect(reason)}")
    end
  end

  def run(_args), do: Mix.raise("Usage: mix leitor.dictionary.import URL_OR_PATH")
end
