defmodule Mix.Tasks.Leitor.Ai.Preview do
  @shortdoc "Generates a scoped development page and preserves its drawing stream for inspection"
  @moduledoc """
  Generates an account-owned creative page using its normal AI authorization.

      mix leitor.ai.preview --user-id UUID --brief tmp/brief.txt --title "Visual study" --format visual_explainer

  Development only. The Markdown stream is saved under ignored `tmp/`, including
  incomplete output when validation or transport fails, so drawing defects can
  be reproduced without repeatedly charging for blind retries. Credentials are
  never written. `--review-only --source path` disables automatic author edits while
  retaining fresh isolation, independent review, normal AI authorization and
  publication only on acceptance. Only a validated result is persisted as a private page.
  """
  use Mix.Task

  alias Leitor.Accounts
  alias Leitor.Accounts.Scope
  alias Leitor.AI
  alias Leitor.AI.Client
  alias Leitor.Figures.Artifacts
  alias Leitor.Figures.Source
  alias Leitor.Language
  alias Leitor.Pages

  @doc "Generates one development preview with the selected account's model, quota and credential boundaries."
  @spec run([String.t()]) :: :ok
  @impl true
  def run(args) do
    if Mix.env() != :dev, do: Mix.raise("This task is available only in development")

    {opts, []} =
      OptionParser.parse!(args,
        strict: [
          user_id: :string,
          brief: :string,
          title: :string,
          format: :string,
          revision: :string,
          source: :string,
          review_only: :boolean
        ]
      )

    if Keyword.get(opts, :review_only, false) and is_nil(opts[:source]),
      do: Mix.raise("Review-only previews require --source; no AI credits were reserved")

    prompt = opts |> Keyword.fetch!(:brief) |> File.read!()
    title = Keyword.get(opts, :title, "Visual study")
    format = Keyword.get(opts, :format, "visual_explainer")
    validate_request!(prompt, format)
    Mix.Task.run("app.start")
    scope = opts |> Keyword.fetch!(:user_id) |> Accounts.get_user!() |> Scope.for_user()
    preferences = Accounts.get_preferences(scope)
    operation = if Leitor.WritingFormat.visual?(format), do: :illustration, else: :write
    revision = revision(scope, opts, preferences)

    client =
      case AI.prepare(scope, operation) do
        {:ok, client} -> client
        {:error, reason} -> Mix.raise("AI preview unavailable (#{reason}); no provider was contacted")
      end

    try do
      generate(scope, client, prompt, title, format, preferences, revision, opts[:review_only] || false)
    after
      AI.finish(scope, client.lease_id)
    end
  end

  defp validate_request!(prompt, format) do
    if String.trim(prompt) == "" or String.length(prompt) > 2000,
      do: Mix.raise("The brief must contain 1–2,000 characters; no AI credits were reserved")

    if is_nil(Leitor.WritingFormat.instruction(format)),
      do: Mix.raise("This writing format is unavailable; no AI credits were reserved")
  end

  defp revision(scope, opts, preferences) do
    case {opts[:source], opts[:revision]} do
      {nil, revision} ->
        revision

      {path, nil} ->
        with {:ok, source} <- Source.new(Jason.decode!(File.read!(path))),
             {:ok, artifact} <-
               Artifacts.store(scope, %{
                 title: source.title,
                 caption: source.caption,
                 model: preferences.writing_model,
                 source: Source.dump(source),
                 report: %{stage: "development_source"},
                 status: "draft"
               }) do
          artifact.id
        else
          {:error, _changeset} -> Mix.raise("Invalid development figure source")
        end

      {_path, _revision} ->
        Mix.raise("Choose either --source or --revision")
    end
  end

  defp generate(scope, client, prompt, title, format, preferences, revision, review_only) do
    File.mkdir_p!("tmp")
    path = Path.expand("tmp/ai-preview-#{System.system_time(:microsecond)}.md")
    File.write!(path, "")
    request = %{prompt: prompt, title: title, context: "", format: format}
    on_delta = fn delta -> File.write!(path, delta, [:append]) end
    Mix.shell().info("Generating with #{client.model}; provisional Markdown: #{path}")

    options =
      client
      |> Client.options()
      |> Keyword.merge(figure_scope: scope, figure_revision: revision, figure_review_only: review_only)

    case Language.generate_page_text(request, on_delta, preferences, options) do
      {:ok, %{"markdown" => markdown}} ->
        {:ok, page} = Pages.create_page(scope, %{"title" => title, "body" => markdown})
        Mix.shell().info("Validated preview saved: /pages/#{page.id}")

      {:error, reason} ->
        Mix.raise("Preview failed (#{reason}); inspect the preserved Markdown stream")
    end
  end
end
