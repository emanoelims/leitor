defmodule Mix.Tasks.Leitor.Figure.Evaluate do
  @shortdoc "Lists frozen quality briefs or explicitly generates one normally authorized example"
  @moduledoc """
  Reproduces the six original-generation quality cases in development.

      mix leitor.figure.evaluate --list
      mix leitor.figure.evaluate --case optical-refraction
      mix leitor.figure.evaluate --case optical-refraction --generate --user-id UUID

  Listing or selecting a brief makes no provider request. `--generate` explicitly
  runs exactly one case through `leitor.ai.preview`, including ordinary account
  credits, selected model, private artifact isolation and independent review.
  Failures do not trigger another paid job. Do not repeatedly rerun failed cases
  without recording them in the evaluation denominator. The versioned manifest
  documents the six-job, 24-credit campaign ceiling; each invocation is one job.
  Never use this task to curate or manually modify an accepted artifact.
  """
  use Mix.Task

  @doc "Lists frozen cases or explicitly starts one ordinary development preview."
  @spec run([String.t()]) :: :ok
  @impl true
  def run(args) do
    {options, []} =
      OptionParser.parse!(args, strict: [list: :boolean, case: :string, generate: :boolean, user_id: :string])

    manifest = :leitor |> Application.app_dir("priv/figure_evaluation.json") |> File.read!() |> Jason.decode!()
    %{"cases" => cases, "max_attempts" => 6, "max_credits" => 24} = manifest

    if options[:list] do
      Enum.each(cases, &Mix.shell().info("#{&1["slug"]} · #{&1["format"]} · #{&1["title"]}"))
    else
      case Enum.find(cases, &(&1["slug"] == options[:case])) do
        nil ->
          Mix.raise("Choose a known --case from --list; no provider was contacted")

        entry ->
          run_case(entry, options)
      end
    end

    :ok
  end

  defp run_case(%{"slug" => slug, "prompt" => prompt, "title" => title, "format" => format}, options) do
    Mix.shell().info(prompt)

    if options[:generate] do
      if Mix.env() != :dev, do: Mix.raise("Paid quality evaluation is development only")
      user = Keyword.fetch!(options, :user_id)
      File.mkdir_p!("tmp/figure-evaluation")
      brief = Path.join("tmp/figure-evaluation", slug <> ".txt")
      File.write!(brief, prompt)
      Mix.Task.reenable("leitor.ai.preview")
      Mix.Task.run("leitor.ai.preview", ["--user-id", user, "--brief", brief, "--title", title, "--format", format])
    end
  end
end
