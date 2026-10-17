defmodule Leitor.Figures.Editor do
  @moduledoc "An iterative coding-tool loop for original figures and revisions. The model writes bounded modules, renders in isolation and sees actual captures before submitting."
  alias Leitor.Figures.Artifacts
  alias Leitor.Figures.Runner
  alias Leitor.Figures.Source
  alias ReqLLM.Context
  alias ReqLLM.Message.ContentPart

  require Logger

  @facets_path Path.expand("../../../assets/vendor/anatomy/facets.mjs", __DIR__)
  @external_resource @facets_path
  @facets_source File.read!(@facets_path)

  @occlusion_path Path.expand("../../../assets/js/figures/kit/occlusion.mjs", __DIR__)
  @external_resource @occlusion_path
  @occlusion_source File.read!(@occlusion_path)

  @mechanics_path Path.expand("../../../assets/js/figures/kit/mechanics.mjs", __DIR__)
  @external_resource @mechanics_path
  @mechanics_source File.read!(@mechanics_path)

  @files ~w(model.mjs geometry.mjs figure.mjs checks.mjs style.css metadata.json)
  @typedoc "Immutable interaction assertions and mechanical check source carried between private coding stages. Nil entries mean no successful full render has frozen that contract yet."
  @type frozen_contracts :: %{experiments: [map()] | nil, checks: String.t() | nil}

  @doc "Creates or refines a program within one reserved output and wall-clock budget. Passing UI and mechanical checks are frozen. A token-exhausted stage can return `{:incomplete, files, continuation}` for private continuation, including its frozen contracts and actual usage; it grants no execution or review evidence. Successful internal render evidence is bound to the exact validated source and cannot be supplied by provider JSON. No shell or arbitrary filesystem tool is exposed."
  @spec write(map(), String.t(), keyword()) ::
          Leitor.Language.result()
          | {:incomplete, map(),
             %{
               output_tokens: pos_integer(),
               usage: [map()],
               contracts: frozen_contracts(),
               contract_revision: Ecto.UUID.t() | nil,
               effort: String.t()
             }}
  def write(state, prompt, options) do
    instruction =
      mode_instruction(state) <>
        "Resolve the assembly topology, joint constraints, axial stack and camera visibility in the pure model before drawing. Record that compact design in model.mjs; do not spend the whole response on a plan. Work in bounded modules, then render and iterate. " <>
        "Iterate from actual images and errors. Prefer patch_file over rewriting entire files. " <>
        "Preserve existing passing experiment contracts; after your first successful render the experiments are frozen. " <>
        "Write checks.mjs before geometry: import your pure model and export synchronous verify(), returning 3–24 unique {name,passed} checks. " <>
        "Call verify_model before building geometry, and after changing mechanical equations: it executes the pure model checks in isolation without requiring the drawing or UI. Fix failed constraints before spending tokens on the illustration. A model-only success never replaces a full render or visual review. " <>
        "Sample a complete cycle, joint closure/contact, travel limits and actual state transitions, not constants or duplicated equations. " <>
        "The existing checks.mjs prefix is frozen after a passing render. Strengthen it only by appending new exported verifyExtra1(), verifyExtra2(), etc.; each returns additional named checks, all of which must pass. Never replace or edit the original assertions. " <>
        repair_strategy(state) <>
        "Never hide expected assertion text or fake evidence to pass tests. If localization conflicts with frozen tests, preserve the tested language and explain the limitation. " <>
        "read_file('kit.md') documents the kit; read_file('facets.mjs') exposes meshes and clipping; read_file('occlusion.mjs') exposes Leitor's bounded opaque surface ordering. read_file('mechanics.mjs') exposes verified involute gears and slider-crank closure. Use it for supported mechanisms instead of approximate teeth or separately positioned pins. No shell, network or external assets are available. " <>
        "Use finish only after render passes and you have inspected all captures for the user's requested craftsmanship. " <>
        "The default mobile view must fit the whole assembly and its travel, not crop the rack ends, base or supports to enlarge a detail. Offer any close-up as an explicitly labeled optional inspection view. The checker measures actual SVG drawing bounds against the mobile viewBox; hiding overflow does not repair framing. " <>
        "Original geometry and simulation code are allowed. Never replace the program with a generic preset.\n" <> prompt

    images = Enum.map(Map.get(state, :review_images, []), &ContentPart.image/1)
    context = ReqLLM.context(Context.user([ContentPart.text(instruction) | images]))
    contracts = frozen_contracts(state)

    editor = %{
      owner: state,
      files: initial_files(state),
      contracts: contracts.experiments,
      check_contract: contracts.checks,
      contract_revision: Map.get(state, :contract_revision),
      require_checks: is_nil(state.baseline),
      context: context,
      options: options,
      remaining: Keyword.fetch!(options, :max_tokens),
      spent: 0,
      rounds: 20,
      effort: Map.get(state, :author_effort, "medium"),
      checked: nil,
      verified: nil,
      done: false,
      usage: []
    }

    turn(editor)
  end

  defp mode_instruction(%{baseline: nil} = state) do
    origin =
      if Map.get(state, :resume),
        do: "Continue the original partial program from its saved modules. Read existing files before changing them. ",
        else: "Create an ORIGINAL interactive figure from empty files using the coding tools. "

    origin <>
      "First read kit.md. Write model.mjs and checks.mjs, then geometry.mjs, figure.mjs and style.css. " <>
      "Write at most one complete module per turn; keep it concise enough to fit the response budget. " <>
      "Write metadata.json with nonempty title, caption, before and after (short Markdown prose), plus 3–6 experiments. " <>
      "Each experiment has name, steps (1–8 items with action, selector, value), selector and contains. " <>
      "Actions are click, fill, press or range; value is a string (empty for click). Assertions check visible text. " <>
      "Optional capture_steps (up to 8 of the same actions) arrange the final screenshot AFTER all experiments pass; use them for a clear scientific pose without changing the tests. " <>
      "Derive shapes, mechanical poses, controls and readouts from one pure model. No prebuilt figure is supplied. "
  end

  defp mode_instruction(_state),
    do:
      "You are editing an existing interactive figure with real coding tools. Read the relevant files and correct observed defects. "

  defp repair_strategy(%{evidence: [_ | _]}) do
    "Review failures require repairing the physical cause, not another cosmetic patch. Rebuild the affected geometry module when needed, preserving exports and passing tests. " <>
      "Put every mechanically relevant XYZ position and axial interval in the pure model and consume those exact values in geometry. Append checks for real 3D overlap/contact and clearance, not only planar alignment. " <>
      "Create actual cut faces and visible bearing seats. A dashed outline, floating contact marker, flat inset or prose is not a replacement for a visible connected solid in the main 3D scene. Preserve earlier fixes, then render and inspect all captures. "
  end

  defp repair_strategy(_state),
    do:
      "Read current modules, make the smallest connected correction, then inspect the captures. Preserve fixes from earlier review rounds. "

  defp initial_files(state) do
    source = Map.get(state, :resume) || state.baseline || %{}
    source = Map.get(source, "completed", source)

    metadata =
      Map.merge(
        Map.new(~w(title caption before after), &{&1, ""}),
        Map.take(source, ~w(title caption before after experiments capture_steps))
      )

    %{
      "model.mjs" => Map.get(source, "model", ""),
      "geometry.mjs" => Map.get(source, "geometry", ""),
      "figure.mjs" => Map.get(source, "figure", ""),
      "checks.mjs" => Map.get(source, "checks", ""),
      "style.css" => Map.get(source, "css", ""),
      "metadata.json" => Jason.encode!(Map.put_new(metadata, "experiments", []))
    }
  end

  defp turn(%{done: true} = editor), do: result(editor)

  defp turn(%{rounds: 0} = editor) do
    if fresh?(editor), do: result(editor), else: {:error, :figure_review_failed}
  end

  defp turn(editor) do
    time = editor.owner.deadline - System.monotonic_time(:millisecond)

    cond do
      time <= 1000 ->
        {:error, :figure_budget_exceeded}

      editor.remaining < 1000 and fresh?(editor) ->
        result(editor)

      editor.remaining < 1000 ->
        incomplete(editor)

      true ->
        editor.owner.progress.(if(is_nil(editor.owner.baseline), do: "building", else: "refining"))

        options =
          Keyword.merge(editor.options,
            max_tokens: min(8192, editor.remaining),
            total_timeout: min(time, 300_000),
            receive_timeout: min(time, 300_000),
            reasoning_effort: :none,
            provider_options: [output_config: %{effort: editor.effort}]
          )

        with {:ok, response} <- editor.owner.adapter.code_step(editor.owner.model, editor.context, tools(), options) do
          editor = account_usage(editor, response, Keyword.fetch!(options, :max_tokens))

          handle_response(editor, response, ReqLLM.Response.tool_calls(response))
        end
    end
  end

  defp incomplete(%{spent: spent} = editor) when spent > 0 do
    with {:ok, attrs} <- attrs(%{editor | require_checks: false}) do
      checkpoint(editor)

      {:incomplete, attrs,
       %{
         output_tokens: editor.spent,
         usage: editor.usage,
         effort: editor.effort,
         contract_revision: editor.contract_revision,
         contracts: %{experiments: editor.contracts, checks: editor.check_contract}
       }}
    end
  end

  defp incomplete(_editor), do: {:error, :figure_budget_exceeded}

  defp account_usage(editor, response, allocated) do
    output = Map.get(response.usage || %{}, :output_tokens, allocated)
    spent = if is_integer(output) and output in 1..allocated, do: output, else: allocated

    usage = %{
      phase: "code_tools",
      output_tokens: spent,
      input_tokens: Map.get(response.usage || %{}, :input_tokens, 0),
      finish_reason: to_string(response.finish_reason),
      effort: editor.effort
    }

    %{
      editor
      | remaining: editor.remaining - spent,
        spent: editor.spent + spent,
        rounds: editor.rounds - 1,
        effort: if(response.finish_reason == :length, do: "low", else: editor.effort),
        usage: editor.usage ++ [usage]
    }
  end

  defp handle_response(editor, response, []) do
    if fresh?(editor) do
      result(editor)
    else
      context =
        Context.append(editor.context, [
          response.message,
          Context.user(next_edit_instruction(response.finish_reason))
        ])

      turn(%{editor | context: context})
    end
  end

  defp handle_response(editor, response, calls) do
    {editor, replies} =
      calls
      |> Enum.with_index()
      |> Enum.reduce({editor, []}, fn {call, index}, {current, replies} ->
        {next, content} = dispatch(current, call, index)
        {next, replies ++ [Context.tool_result(call.id, content)]}
      end)

    case Context.append_tool_exchange(editor.context, response, replies) do
      {:ok, context} ->
        context =
          if response.finish_reason == :length,
            do: Context.append(context, [Context.user(next_edit_instruction(:length))]),
            else: context

        turn(%{editor | context: context})

      {:error, _} ->
        {:error, :invalid_response}
    end
  end

  defp next_edit_instruction(:length) do
    "Your previous response reached its output limit before saving an edit. Do not repeat the full plan. " <>
      "Use write_file or patch_file now to save one small, complete piece of the missing implementation. " <>
      "Keep this edit under roughly 2,000 output tokens; build a larger module through several exact patches. " <>
      "Continue from saved files, preserve the mechanical and interaction contracts, then obtain a fresh passing render."
  end

  defp next_edit_instruction(_reason),
    do: "The current program has not passed a fresh render. Use the coding tools and render before finishing."

  defp dispatch(editor, call, index) do
    cond do
      editor.done -> {editor, "The verified program has already been submitted."}
      index >= 6 -> {editor, "Only six tools can execute per turn; request remaining operations in the next turn."}
      editor.owner.deadline - System.monotonic_time(:millisecond) <= 1000 -> {editor, "The job deadline has expired."}
      true -> execute(editor, call.function.name, call.function.arguments)
    end
  end

  defp execute(editor, name, json) do
    Logger.debug("Figure editor tool: #{name}")

    case Jason.decode(json) do
      {:ok, args} when is_map(args) -> action(editor, name, args)
      _ -> {editor, "Invalid JSON arguments"}
    end
  end

  defp action(editor, "read_file", %{"path" => "facets.mjs"}), do: {editor, @facets_source}

  defp action(editor, "read_file", %{"path" => "occlusion.mjs"}), do: {editor, @occlusion_source}

  defp action(editor, "read_file", %{"path" => "mechanics.mjs"}), do: {editor, @mechanics_source}

  defp action(editor, "read_file", %{"path" => "kit.md"}) do
    {editor, File.read!(Application.app_dir(:leitor, "priv/figure_author.md"))}
  end

  defp action(editor, "read_file", %{"path" => path}) when path in @files, do: {editor, Map.fetch!(editor.files, path)}

  defp action(editor, "write_file", %{"path" => path, "content" => content})
       when path in @files and is_binary(content) and byte_size(content) <= 60_000 do
    changed = %{editor | files: Map.put(editor.files, path, content), checked: nil, verified: nil, effort: "medium"}
    checkpoint(changed)
    {changed, "Saved #{path}. Render to verify it."}
  end

  defp action(editor, "patch_file", %{"path" => path, "old" => old, "new" => new})
       when path in @files and is_binary(old) and old != "" and is_binary(new) and byte_size(new) <= 60_000 do
    current = Map.fetch!(editor.files, path)

    if length(String.split(current, old)) == 2 do
      updated = String.replace(current, old, new, global: false)
      action(editor, "write_file", %{"path" => path, "content" => updated})
    else
      {editor, "The old text must match exactly once. Read the file and choose a precise patch."}
    end
  end

  defp action(editor, "render", _args) do
    if editor.owner.deadline - System.monotonic_time(:millisecond) < 100_000 do
      {editor, "Not enough job time remains to start another isolated render."}
    else
      render(editor)
    end
  end

  defp action(editor, "verify_model", _args) do
    runner = Application.get_env(:leitor, :figure_runner_adapter, Runner)

    files = %{
      "model.mjs" => editor.files["model.mjs"],
      "checks.mjs" => editor.files["checks.mjs"],
      "geometry.mjs" => "",
      "figure.mjs" => "export function mount(){return ()=>{}}",
      "model_checks_required" => true,
      "model_only" => true,
      "css" => "",
      "experiments" => [],
      "capture_steps" => []
    }

    cond do
      editor.owner.deadline - System.monotonic_time(:millisecond) < 100_000 ->
        {editor, "Not enough job time remains for isolated model verification."}

      String.trim(editor.files["checks.mjs"]) == "" ->
        {editor, "Write checks.mjs before model verification."}

      true ->
        case runner.check(files) do
          {:ok, result} -> {editor, Jason.encode!(result.report)}
          {:error, reason} -> {editor, Atom.to_string(reason)}
        end
    end
  end

  defp action(editor, "finish", _args) do
    if fresh?(editor),
      do: {%{editor | done: true}, "Ready for independent review"},
      else: {editor, "Render must pass after the last edit before finishing"}
  end

  defp action(editor, _name, _args), do: {editor, "Unknown tool, file or invalid arguments"}

  defp render(editor) do
    editor.owner.progress.("testing")
    runner = Application.get_env(:leitor, :figure_runner_adapter, Runner)

    with {:ok, attrs} <- attrs(editor),
         {:ok, source} <- Source.new(attrs),
         {:ok, result} <- runner.check(Source.files(source)) do
      stored =
        persist(editor, Source.dump(source), %{stage: "render", execution: result.report}, List.first(result.images))

      checked = if result.report["ok"], do: fingerprint(editor)
      verified = if checked, do: %{source: Source.dump(source), result: result}
      content = [ContentPart.text(Jason.encode!(result.report)) | Enum.map(result.images, &ContentPart.image/1)]
      contracts = if result.report["ok"], do: source.experiments, else: editor.contracts
      check_contract = if result.report["ok"], do: check_contract(Source.dump(source)), else: editor.check_contract

      contract_revision =
        case stored do
          {:ok, artifact} when not is_nil(checked) -> artifact.id
          _ -> editor.contract_revision
        end

      {%{
         editor
         | checked: checked,
           verified: verified,
           contracts: contracts,
           check_contract: check_contract,
           contract_revision: contract_revision
       }, content}
    else
      {:error, %Ecto.Changeset{} = changeset} ->
        {editor,
         Jason.encode!(%{
           validation_errors: Map.new(changeset.errors, fn {field, {message, _}} -> {Atom.to_string(field), message} end)
         })}

      {:error, reason} when is_atom(reason) ->
        {editor, Atom.to_string(reason)}

      _ ->
        {editor, "Invalid program metadata"}
    end
  end

  defp attrs(editor) do
    case Jason.decode(Map.fetch!(editor.files, "metadata.json")) do
      {:ok, metadata} when is_map(metadata) -> attrs(editor, metadata)
      _ -> {:error, :invalid_response}
    end
  end

  defp attrs(editor, metadata) do
    with :ok <- validate_contracts(editor, metadata) do
      {:ok,
       Map.merge(metadata, %{
         "model" => editor.files["model.mjs"],
         "geometry" => editor.files["geometry.mjs"],
         "figure" => editor.files["figure.mjs"],
         "css" => editor.files["style.css"],
         "checks" => editor.files["checks.mjs"]
       })}
    end
  end

  defp validate_contracts(editor, metadata) do
    cond do
      not is_nil(editor.contracts) and metadata["experiments"] != editor.contracts ->
        {:error, :frozen_experiments}

      editor.require_checks and String.trim(editor.files["checks.mjs"]) == "" ->
        {:error, :missing_model_checks}

      not is_nil(editor.check_contract) and not String.starts_with?(editor.files["checks.mjs"], editor.check_contract) ->
        {:error, :frozen_model_checks}

      true ->
        :ok
    end
  end

  defp fingerprint(editor), do: :crypto.hash(:sha256, Jason.encode!(editor.files))
  defp fresh?(editor), do: editor.checked == fingerprint(editor)

  defp check_contract(%{"checks" => checks}) when is_binary(checks) and checks != "", do: checks
  defp check_contract(_source), do: nil

  defp frozen_contracts(%{frozen_contracts: %{experiments: _, checks: _} = contracts}), do: contracts

  defp frozen_contracts(state),
    do: %{
      experiments: if(is_map(state.baseline), do: state.baseline["experiments"]),
      checks: check_contract(state.baseline)
    }

  defp result(editor) do
    with {:ok, attrs} <- attrs(editor) do
      {:ok,
       attrs
       |> Map.put("__figure_output_tokens", editor.spent)
       |> Map.put("__figure_usage", editor.usage)
       |> Map.put("__figure_verified", editor.verified)}
    end
  end

  defp checkpoint(editor) do
    with {:ok, attrs} <- attrs(%{editor | require_checks: false}) do
      persist(editor, attrs, %{stage: "coding", usage: editor.usage}, nil)
    end
  end

  defp persist(editor, attrs, report, preview) do
    history =
      editor.owner
      |> Map.get(:evidence, [])
      |> Enum.map(fn evidence -> %{"visual" => Map.get(evidence, :visual) || Map.get(evidence, "visual")} end)
      |> Enum.reject(&is_nil(&1["visual"]))
      |> Enum.take(-6)

    report =
      report
      |> Map.put(:history, history)
      |> checkpoint_recovery(editor)

    result =
      Artifacts.store(editor.owner.scope, %{
        title: "Figure coding draft",
        caption: "An isolated coding-tool revision.",
        model: editor.owner.model,
        source: attrs,
        report: report,
        preview: preview,
        status: "draft"
      })

    case result do
      {:ok, artifact} -> Map.get(editor.owner, :checkpoint, fn _id -> :ok end).(artifact.id)
      {:error, _changeset} -> :ok
    end

    result
  end

  defp checkpoint_recovery(report, %{contract_revision: nil} = editor)
       when not is_nil(editor.contracts) or not is_nil(editor.check_contract), do: report

  defp checkpoint_recovery(report, editor),
    do: Map.put(report, :recovery, %{version: 1, contracts_revision: editor.contract_revision, effort: editor.effort})

  defp tools do
    string = %{type: "string"}
    path = %{type: "string", enum: @files}

    [
      tool("read_file", "Read an existing program module or kit.md", %{path: string}),
      tool("write_file", "Write a complete bounded module or metadata file", %{path: path, content: string}),
      tool("patch_file", "Replace one exact occurrence in a program file", %{path: path, old: string, new: string}),
      tool(
        "verify_model",
        "Run sampled mechanical checks in isolation before drawing; returns no publication evidence",
        %{}
      ),
      tool("render", "Compile, test all controls and inspect screenshots in the isolated browser", %{}),
      tool("finish", "Submit the currently verified program for independent visual review", %{})
    ]
  end

  defp tool(name, description, properties) do
    schema = %{type: "object", additionalProperties: false, properties: properties, required: Map.keys(properties)}

    ReqLLM.tool(
      name: name,
      description: description,
      parameter_schema: schema,
      callback: fn _args -> {:error, :manual_execution_only} end
    )
  end
end
