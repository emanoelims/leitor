defmodule Mix.Tasks.Leitor.Figure.Check do
  @shortdoc "Compiles a development figure in isolation and saves its visual evidence"
  @moduledoc """
  Checks a complete development source JSON without calling an AI provider.

      mix leitor.figure.check --source tmp/figure.json --output tmp/figure-check

  This does not publish an artifact or grant execution in the reader. Captures
  remain under the project's ignored tmp directory for human visual inspection.
  """
  use Mix.Task

  alias Leitor.Figures.Runner
  alias Leitor.Figures.Source

  @impl true
  def run(args) do
    if Mix.env() != :dev, do: Mix.raise("This task is available only in development")
    {opts, []} = OptionParser.parse!(args, strict: [source: :string, output: :string])
    directory = opts |> Keyword.fetch!(:output) |> Path.expand()
    if !String.starts_with?(directory, Path.expand("tmp") <> "/"), do: Mix.raise("Output must be inside tmp/")
    Mix.Task.run("app.start")
    {:ok, source} = Source.new(Jason.decode!(File.read!(Keyword.fetch!(opts, :source))))
    {:ok, result} = Runner.check(Source.files(source))
    File.mkdir_p!(directory)
    File.write!(Path.join(directory, "report.json"), Jason.encode!(result.report, pretty: true))

    result.report["images"]
    |> Enum.zip(result.images)
    |> Enum.each(fn {name, png} -> File.write!(Path.join(directory, name), png) end)

    Mix.shell().info("Isolated check: #{result.report["ok"]}; evidence: #{directory}")
  end
end
