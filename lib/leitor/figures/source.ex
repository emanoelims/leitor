defmodule Leitor.Figures.Source do
  @moduledoc "Validated authored modules and browser experiments. Validation does not grant execution privileges."
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field :title, :string
    field :caption, :string
    field :before, :string
    field :after, :string
    field :figure, :string
    field :geometry, :string
    field :model, :string
    field :css, :string
    field :checks, :string, default: ""
    field :experiments, {:array, :map}
    field :capture_steps, {:array, :map}, default: []
  end

  @typedoc "A bounded program proposal, including observable interaction experiments."
  @type t :: %__MODULE__{}
  @fields ~w(title caption before after figure geometry model css checks experiments capture_steps)a

  @doc "Validates source sizes and experiment actions before any file is created."
  @spec new(map()) :: {:ok, t()} | {:error, Ecto.Changeset.t(t())}
  def new(attrs) do
    changeset = %__MODULE__{} |> cast(attrs, @fields) |> validate_required(@fields -- [:capture_steps, :checks])
    changeset = update_change(changeset, :checks, &(&1 || ""))
    changeset = validate_length(changeset, :checks, max: 20_000)
    changeset = update_change(changeset, :capture_steps, &(&1 || []))
    changeset = Enum.reduce([:figure, :geometry, :model, :css], changeset, &validate_length(&2, &1, max: 60_000))
    changeset = Enum.reduce([:before, :after], changeset, &validate_length(&2, &1, max: 3500))

    changeset
    |> validate_length(:title, max: 100)
    |> validate_length(:caption, max: 600)
    |> validate_length(:experiments, min: 3, max: 6)
    |> validate_length(:capture_steps, max: 8)
    |> validate_change(:capture_steps, fn :capture_steps, steps ->
      if Enum.all?(steps, &step?/1), do: [], else: [capture_steps: "contain an invalid action"]
    end)
    |> validate_change(:experiments, fn :experiments, experiments ->
      if Enum.all?(experiments, &experiment?/1), do: [], else: [experiments: "contain an invalid action or assertion"]
    end)
    |> apply_action(:validate)
  end

  defp experiment?(%{"name" => name, "steps" => steps, "selector" => selector, "contains" => contains})
       when is_list(steps) and length(steps) in 1..8 do
    short?(name, 100) and short?(selector, 200) and short?(contains, 300) and Enum.all?(steps, &step?/1)
  end

  defp experiment?(_), do: false

  defp step?(%{"action" => action, "selector" => selector, "value" => value}) do
    action in ~w(click fill press range) and short?(selector, 200) and is_binary(value) and byte_size(value) <= 1000
  end

  defp step?(_), do: false
  defp short?(value, max), do: is_binary(value) and byte_size(value) in 1..max

  @doc "Returns the exact files and experiment request accepted by the isolated runner. Program figures require observed time-dependent mechanism motion as well as direct interaction checks; model-only verification provides no motion evidence."
  @spec files(t()) :: map()
  def files(source) do
    %{
      "figure.mjs" => source.figure,
      "geometry.mjs" => source.geometry,
      "model.mjs" => source.model,
      "checks.mjs" => if(source.checks == "", do: "export function verify(){return []}", else: source.checks),
      "model_checks_required" => source.checks != "",
      "motion_required" => true,
      "css" => source.css,
      "experiments" => source.experiments,
      "capture_steps" => source.capture_steps
    }
  end

  @doc "Returns portable string-keyed source data for coding-tool continuations and private storage."
  @spec dump(t()) :: map()
  def dump(source), do: source |> Ecto.embedded_dump(:json) |> Jason.encode!() |> Jason.decode!()

  @doc "Returns the provider's structural schema; changesets enforce all local bounds."
  @spec schema() :: map()
  def schema do
    string = %{type: "string"}

    step = %{
      type: "object",
      additionalProperties: false,
      required: ~w(action selector value),
      properties: %{
        action: %{type: "string", enum: ~w(click fill press range)},
        selector: string,
        value: %{type: "string"}
      }
    }

    experiment = %{
      type: "object",
      additionalProperties: false,
      required: ~w(name steps selector contains),
      properties: %{
        name: string,
        steps: %{type: "array", items: step},
        selector: string,
        contains: string
      }
    }

    properties = Map.new(~w(title caption before after figure geometry model css), &{&1, string})
    properties = Map.put(properties, "checks", string)
    properties = Map.put(properties, "experiments", %{type: "array", items: experiment})
    properties = Map.put(properties, "capture_steps", %{type: "array", items: step})
    %{type: "object", additionalProperties: false, required: Map.keys(properties), properties: properties}
  end
end
