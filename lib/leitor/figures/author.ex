defmodule Leitor.Figures.Author do
  @moduledoc "Authors a program in bounded modules rather than one oversized JSON response. Each phase sees the real exports of its dependencies."
  alias Leitor.Figures.Artifacts
  alias Leitor.Figures.Source

  require Logger

  @doc "Streams the model and metadata, then geometry and interface source, sharing one reserved output budget."
  @spec write(map(), String.t(), keyword()) :: Leitor.Language.result()
  def write(state, prompt, options) do
    tokens = Keyword.fetch!(options, :max_tokens)
    plan_budget = div(tokens * 40, 100)
    view_reserve = div(tokens, 4)
    schema = Source.schema()

    reusable? = not is_nil(Map.get(state, :baseline))

    schema = %{
      schema
      | properties: plan_properties(schema.properties, reusable?),
        required: ["reuse_model" | schema.required -- ~w(geometry figure)]
    }

    instruction =
      prompt <>
        "\nAUTHORING PHASE 1: return model, checks, CSS, metadata and experiments ONLY. " <>
        "The model must export createState() and transition(state,action), and may export more useful helpers. " <>
        "Plan stable control IDs matching your experiments. Geometry and figure modules will be written in subsequent phases. " <>
        "Keep the pure state implementation precise and concise. Do not include geometry or figure properties. " <>
        "If the supplied previous model already works and only the drawing or UI needs repair, set reuse_model=true: leave model empty and experiments empty; the host will retain the exact previous model and passing experiment contracts. " <>
        "Otherwise set reuse_model=false and supply a complete nonempty model and 3–6 meaningful experiments. All other metadata and CSS must be complete."

    with {:ok, plan, plan_usage} <- plan_stage(state, instruction, schema, options, plan_budget),
         :ok <- checkpoint(state, plan, "geometry_pending"),
         geometry_budget = tokens - plan_usage.output_tokens - view_reserve,
         {:ok, geometry, geometry_usage} <- geometry_stage(state, prompt, plan, options, geometry_budget),
         :ok <- checkpoint(state, Map.put(plan, "geometry", geometry), "figure_pending"),
         view_budget = tokens - plan_usage.output_tokens - geometry_usage.output_tokens,
         {:ok, figure, view_usage} <- view(state, prompt, Map.put(plan, "geometry", geometry), options, view_budget) do
      usage = [plan_usage, geometry_usage, view_usage]

      attrs =
        plan
        |> Map.put("geometry", geometry)
        |> Map.put("figure", figure)
        |> Map.put("__figure_output_tokens", Enum.sum(Enum.map(usage, & &1.output_tokens)))
        |> Map.put("__figure_usage", usage)

      {:ok, attrs}
    end
  end

  defp plan_properties(properties, reusable?) do
    properties = properties |> Map.drop(~w(geometry figure)) |> Map.put("reuse_model", %{type: "boolean"})

    if reusable? do
      properties
      |> Map.put("model", %{type: "string"})
      |> Map.update!("experiments", &Map.put(&1, :minItems, 0))
    else
      Map.put(properties, "reuse_model", %{type: "boolean", enum: [false]})
    end
  end

  defp plan_stage(state, instruction, schema, options, budget) do
    case reusable_source(state) do
      nil ->
        with {:ok, plan, usage} <- ask(state, :object, instruction, schema, options, budget, %{}, "model") do
          validated_plan(state, plan, usage)
        end

      completed ->
        {:ok, Map.drop(completed, ~w(geometry figure)),
         %{output_tokens: 0, input_tokens: 0, reasoning_tokens: 0, phase: "model_reused"}}
    end
  end

  defp validated_plan(state, plan, usage) do
    case complete_plan(state, plan) do
      {:ok, completed} ->
        {:ok, completed, usage}

      {:error, _} = error ->
        Artifacts.store(state.scope, %{
          title: "Incomplete figure",
          caption: "Model phase failed validation.",
          model: state.model,
          source: %{completed: plan, phase: "model_invalid"},
          report: %{error: "invalid_model_contract", usage: usage},
          status: "draft"
        })

        error
    end
  end

  defp complete_plan(state, %{"reuse_model" => true} = plan) do
    with baseline when is_map(baseline) <- Map.get(state, :baseline),
         {:ok, _source} <- Source.new(baseline) do
      plan =
        plan
        |> Map.put("model", Map.fetch!(baseline, "model"))
        |> Map.put("checks", Map.get(baseline, "checks", ""))
        |> Map.put("experiments", Map.fetch!(baseline, "experiments"))

      validate_plan(plan)
    else
      _ -> {:error, :invalid_response}
    end
  end

  defp complete_plan(_state, plan), do: validate_plan(plan)

  defp validate_plan(plan) do
    placeholders = Map.merge(plan, %{"figure" => "export function mount(){}", "geometry" => "export const shape=1"})

    case Source.new(placeholders) do
      {:ok, _source} -> {:ok, Map.delete(plan, "reuse_model")}
      {:error, _changeset} -> {:error, :invalid_response}
    end
  end

  defp geometry_stage(state, prompt, plan, options, budget) do
    case reusable_source(state) do
      %{"geometry" => geometry} ->
        {:ok, geometry, %{output_tokens: 0, input_tokens: 0, reasoning_tokens: 0, phase: "geometry_reused"}}

      _ ->
        geometry(state, prompt, plan, options, budget)
    end
  end

  defp reusable_source(state) do
    with %{"completed" => completed} when is_map(completed) <- Map.get(state, :resume),
         placeholders =
           Map.merge(%{"figure" => "export function mount(){}", "geometry" => "export const shape=1"}, completed),
         {:ok, _source} <- Source.new(placeholders) do
      completed
    else
      _ -> nil
    end
  end

  defp checkpoint(state, completed, phase) do
    attrs = %{
      title: Map.fetch!(completed, "title"),
      caption: Map.fetch!(completed, "caption"),
      model: state.model,
      source: %{completed: completed, phase: phase},
      report: %{stage: phase},
      status: "draft"
    }

    case Artifacts.store(state.scope, attrs) do
      {:ok, _revision} -> :ok
      {:error, _changeset} -> {:error, :invalid_response}
    end
  end

  defp geometry(state, prompt, plan, options, budget) do
    instruction =
      prompt <>
        "\nAUTHORING PHASE 2: write ONLY the complete geometry.mjs JavaScript module, without fences or prose. " <>
        "Export render(state,options={}) returning a COMPLETE <svg class=\"iso-svg\"> string, including viewBox. " <>
        "Its scene must fit width 900 and respond to the actual model state. The interface will call this export. " <>
        "Use only documented kit APIs and the real model exports below. Spend the available code budget on purposeful crafted detail and correct cutaway depth. " <>
        "MODEL, PRESENTATION AND EXPERIMENT CONTRACT:\n" <> Jason.encode!(plan)

    case ask(state, :text, instruction, nil, options, budget, plan, "geometry") do
      {:ok, %{"markdown" => source}, usage} -> {:ok, unfence(source), usage}
      {:error, _} = error -> error
      _ -> {:error, :invalid_response}
    end
  end

  defp view(state, prompt, plan, options, budget) do
    instruction =
      prompt <>
        "\nAUTHORING PHASE 3: write ONLY the complete figure.mjs JavaScript module, without fences or prose. " <>
        "Export mount(root,env) and return cleanup. Implement the REAL control IDs and experiment outcomes below. " <>
        "Import render from './geometry.mjs', plus the ACTUAL model exports. Do not invent imports. " <>
        "Tie controls, all rendered poses and live status to one consistent state. Reduced motion must settle immediately. " <>
        "Do not redraw unchanged geometry every frame or replace focused controls; update the drawing and controls separately. " <>
        "ACTUAL MODULES, CSS AND EXPERIMENT CONTRACT:\n" <> Jason.encode!(plan)

    case ask(state, :text, instruction, nil, options, budget, plan, "figure") do
      {:ok, %{"markdown" => source}, usage} -> {:ok, unfence(source), usage}
      {:error, _} = error -> error
      _ -> {:error, :invalid_response}
    end
  end

  defp ask(state, kind, prompt, schema, options, tokens, previous, phase) do
    Logger.debug("Figure author phase #{phase}, output budget #{tokens}")
    state.progress.(phase)
    remaining = state.deadline - System.monotonic_time(:millisecond)

    if remaining <= 1000 do
      {:error, :figure_budget_exceeded}
    else
      collect(
        state,
        kind,
        prompt,
        schema,
        Keyword.merge(options,
          max_tokens: tokens,
          total_timeout: min(remaining, 360_000),
          stream_idle_timeout: min(remaining, 360_000),
          receive_timeout: min(remaining, 360_000),
          reasoning_effort: :none,
          provider_options: [output_config: %{effort: "low"}]
        ),
        previous,
        phase
      )
    end
  end

  defp collect(state, kind, prompt, schema, options, previous, phase) do
    buffer = :ets.new(:figure_source, [:set, :private])
    :ets.insert(buffer, [{:size, 0}, {:chunks, []}, {:usage, nil}])
    callback = fn fragment -> append(buffer, fragment) end
    options = Keyword.put(options, :usage_callback, fn usage -> :ets.insert(buffer, {:usage, usage}) end)

    try do
      result =
        case kind do
          :object -> state.adapter.stream_object(state.model, prompt, schema, callback, options)
          :text -> stream_code(state, prompt, callback, options, phase)
        end

      if match?({:error, _}, result), do: save_partial(state, buffer, previous, phase)

      case result do
        {:ok, value} -> {:ok, value, usage(buffer, Keyword.fetch!(options, :max_tokens), phase)}
        {:error, _} = error -> error
      end
    after
      :ets.delete(buffer)
    end
  end

  defp stream_code(state, prompt, callback, options, "geometry") do
    images = Map.get(state, :review_images, [])

    if images != [] and function_exported?(state.adapter, :stream_visual, 5),
      do: state.adapter.stream_visual(state.model, prompt, images, callback, options),
      else: state.adapter.stream(state.model, prompt, callback, options)
  end

  defp stream_code(state, prompt, callback, options, _phase),
    do: state.adapter.stream(state.model, prompt, callback, options)

  defp usage(buffer, allocated, phase) do
    [{:usage, usage}] = :ets.lookup(buffer, :usage)
    counters = if is_map(usage), do: usage, else: %{}
    output = Map.get(counters, :output_tokens)
    used = if is_integer(output) and output in 1..allocated, do: output, else: allocated

    %{
      phase: phase,
      output_tokens: used,
      input_tokens: Map.get(counters, :input_tokens, 0),
      reasoning_tokens: Map.get(counters, :reasoning_tokens, 0)
    }
  end

  defp append(buffer, fragment) do
    if :ets.update_counter(buffer, :size, byte_size(fragment)) <= 200_000 do
      [{:chunks, chunks}] = :ets.lookup(buffer, :chunks)
      :ets.insert(buffer, {:chunks, [fragment | chunks]})
    end
  end

  defp save_partial(state, buffer, previous, phase) do
    [{:chunks, chunks}] = :ets.lookup(buffer, :chunks)
    partial = chunks |> Enum.reverse() |> IO.iodata_to_binary()

    Artifacts.store(state.scope, %{
      title: "Incomplete figure",
      caption: "Generation ended before validation.",
      model: state.model,
      source: %{completed: previous, partial_source: partial, phase: phase},
      report: %{error: "provider_interrupted"},
      status: "draft"
    })
  end

  defp unfence(source) do
    source |> String.trim() |> String.replace(~r/\A```(?:javascript|js|mjs)?\s*\n/, "") |> String.replace(~r/\n```\z/, "")
  end
end
