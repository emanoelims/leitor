defmodule Mix.Tasks.Leitor.Figure.Curate do
  @shortdoc "Creates a private development study with an explicit operator review"
  @moduledoc """
  Creates a private development study after a fresh isolated check and a recorded
  operator verdict. This does not change the automatic author/reviewer pipeline.

      mix leitor.figure.curate --user-id UUID --source tmp/source.json --review tmp/review.json --previous UUID

  The bounded review JSON must explicitly identify its reviewer, rationale and
  limitations, with decision `preview`. An optional previous revision must belong
  to the selected account; its automated critique is retained. This command is
  unavailable outside development and never calls an AI provider.
  """
  use Mix.Task

  alias Leitor.Accounts
  alias Leitor.Accounts.Scope
  alias Leitor.Figures.Artifacts
  alias Leitor.Figures.Runner
  alias Leitor.Figures.Source
  alias Leitor.Pages
  alias Leitor.Repo

  @impl true
  def run(args) do
    if Mix.env() != :dev, do: Mix.raise("This task is available only in development")

    {opts, []} =
      OptionParser.parse!(args,
        strict: [user_id: :string, source: :string, review: :string, previous: :string, page: :string]
      )

    review = opts |> Keyword.fetch!(:review) |> read_review!()
    {:ok, source} = opts |> Keyword.fetch!(:source) |> File.read!() |> Jason.decode!() |> Source.new()
    Mix.Task.run("app.start")
    scope = opts |> Keyword.fetch!(:user_id) |> Accounts.get_user!() |> Scope.for_user()
    previous = previous!(scope, opts[:previous])
    page = if opts[:page], do: Pages.get_page!(scope, opts[:page])

    case Runner.check(Source.files(source)) do
      {:ok, %{report: %{"ok" => true}} = result} -> publish!(scope, source, result, review, previous, page)
      _ -> Mix.raise("The isolated check did not pass; no executable study was stored")
    end
  end

  defp read_review!(path) do
    bytes = File.read!(path)
    if byte_size(bytes) > 6000, do: Mix.raise("The operator review exceeds its size limit")
    review = Jason.decode!(bytes)

    valid? =
      is_map(review) and review["decision"] == "preview" and
        Enum.all?(~w(reviewer rationale limitations), fn key ->
          value = review[key]
          is_binary(value) and String.trim(value) != ""
        end)

    if not valid?, do: Mix.raise("An explicit reviewer, preview verdict, rationale and limitations are required")
    review
  end

  defp previous!(_scope, nil), do: nil

  defp previous!(scope, id) do
    case Artifacts.get_revision(scope, id) do
      nil -> Mix.raise("The previous revision is unavailable to this account")
      revision -> %{id: revision.id, report: revision.report}
    end
  end

  defp publish!(scope, source, result, review, previous, page) do
    attrs = %{
      title: source.title,
      caption: source.caption,
      model: "operator-curated",
      source: Source.dump(source),
      report: %{
        execution: result.report,
        operator_review: review,
        previous_automated_revision: previous,
        stage: "curated_development_preview"
      },
      status: "ready",
      bundle: result.bundle,
      style: result.style,
      preview: List.first(result.images)
    }

    {:ok, page} =
      Repo.transaction(fn ->
        with {:ok, artifact} <- Artifacts.store(scope, attrs),
             reference = %{
               engine: "anatomy-program",
               version: 1,
               title: source.title,
               caption: source.caption,
               artifact_id: artifact.id
             },
             markdown =
               source.before <> "\n\n```leitor-figure\n" <> Jason.encode!(reference) <> "\n```\n\n" <> source.after,
             {:ok, page} <- save_page(scope, page, %{"title" => source.title, "body" => markdown}) do
          page
        else
          {:error, _} -> Repo.rollback(:invalid_study)
        end
      end)

    Mix.shell().info("Private study saved with explicit operator review: /pages/#{page.id}")
  end

  defp save_page(scope, nil, attrs), do: Pages.create_page(scope, attrs)
  defp save_page(scope, page, attrs), do: Pages.update_page(scope, page, attrs)
end
