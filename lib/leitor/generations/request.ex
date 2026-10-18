defmodule Leitor.Generations.Request do
  @moduledoc "Validated generation instructions and the editor snapshot needed for explicit recovery."
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field :prompt, :string
    field :context, :string, default: ""
    field :title, :string, default: "Untitled"
    field :format, :string, default: "visual_explainer"
    field :draft_body, :string, default: ""
    field :document, :map
    field :insertion, :integer, default: 1
    field :base_revision_id, Ecto.UUID
    field :replace_from, :integer
    field :replace_to, :integer
  end

  @typedoc "An owned, bounded editor request; it contains no provider credentials."
  @type t :: %__MODULE__{}

  @doc "Casts and validates generation instructions and an optional rich-editor snapshot. Explicitly nil optional draft strings normalize to empty text before authorization."
  @spec changeset(t(), map()) :: Ecto.Changeset.t(t())
  def changeset(request, attrs) do
    request
    |> cast(attrs, [
      :prompt,
      :context,
      :title,
      :format,
      :draft_body,
      :document,
      :insertion,
      :base_revision_id,
      :replace_from,
      :replace_to
    ])
    |> update_change(:context, &(&1 || ""))
    |> update_change(:draft_body, &(&1 || ""))
    |> validate_required([:prompt, :title, :format, :insertion])
    |> validate_length(:prompt, min: 1, max: 2000)
    |> validate_length(:context, max: 24_000)
    |> validate_length(:title, max: 180)
    |> validate_length(:draft_body, max: 300_000)
    |> validate_inclusion(:format, Enum.map(Leitor.WritingFormat.options(), &elem(&1, 1)))
    |> validate_number(:insertion, greater_than_or_equal_to: 0, less_than_or_equal_to: 1_000_000)
    |> validate_number(:replace_from, greater_than_or_equal_to: 0, less_than_or_equal_to: 1_000_000)
    |> validate_number(:replace_to, greater_than: 0, less_than_or_equal_to: 1_000_000)
    |> validate_revision_range()
    |> validate_change(:document, fn :document, doc ->
      if doc["type"] == "doc" and byte_size(Jason.encode!(doc)) <= 900_000,
        do: [],
        else: [document: "must be a bounded editor document"]
    end)
  end

  defp validate_revision_range(changeset) do
    if get_field(changeset, :base_revision_id) do
      changeset
      |> validate_required([:replace_from, :replace_to])
      |> validate_number(:replace_to, greater_than: get_field(changeset, :replace_from) || 0)
    else
      changeset
    end
  end

  @doc "Returns the AI-facing fields; recovery-only editor data is never sent to the provider."
  @spec instruction(t()) :: map()
  def instruction(request), do: Map.take(request, [:prompt, :context, :title, :format])
end
