defmodule Leitor.Illustration.Scene do
  @moduledoc "A rich vector scene and its independently animated layers, encoded as bounded JSON in leitor-scene Markdown fences."
  use Ecto.Schema

  import Ecto.Changeset

  alias Leitor.Illustration.Motion
  alias Leitor.Illustration.SVG

  @primary_key false
  embedded_schema do
    field :svg, :string
    embeds_many :animations, Motion
  end

  @typedoc "Validated vector source with up to sixteen app-owned animations."
  @type t :: %__MODULE__{}
  @doc "Validates scene data, all SVG references and every animation target. Invalid data returns a changeset."
  @spec new(map()) :: {:ok, t()} | {:error, Ecto.Changeset.t(t())}
  def new(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:svg])
    |> validate_required([:svg])
    |> validate_length(:svg, max: 65_536, count: :bytes)
    |> cast_embed(:animations, with: &Motion.changeset/2)
    |> validate_length(:animations, max: 16)
    |> validate_targets()
    |> apply_action(:validate)
  end

  @doc "Decodes at most 96 KB of scene JSON. Malformed objects and invalid artwork return invalid_scene."
  @spec from_json(term()) :: {:ok, t()} | {:error, :invalid_scene}
  def from_json(json) when is_binary(json) and byte_size(json) <= 98_304 do
    with {:ok, attrs} when is_map(attrs) <- Jason.decode(json),
         {:ok, scene} <- new(attrs) do
      {:ok, scene}
    else
      _ -> {:error, :invalid_scene}
    end
  end

  def from_json(_), do: {:error, :invalid_scene}
  @doc "Returns normalized animation descriptions with isolated target IDs, suitable for browser playback."
  @spec animations(t(), SVG.t()) :: [map()]
  def animations(scene, svg) do
    Enum.map(scene.animations, fn motion ->
      motion |> Map.from_struct() |> Map.delete(:__meta__) |> Map.update!(:target, &Map.fetch!(svg.ids, &1))
    end)
  end

  defp validate_targets(changeset) do
    case SVG.prepare(get_field(changeset, :svg)) do
      {:ok, svg} ->
        if Enum.all?(get_field(changeset, :animations, []), &Map.has_key?(svg.ids, &1.target)),
          do: changeset,
          else: add_error(changeset, :animations, "must target existing SVG layers")

      {:error, _} ->
        add_error(changeset, :svg, "is invalid")
    end
  end
end
