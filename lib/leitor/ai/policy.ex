defmodule Leitor.AI.Policy do
  @moduledoc "Validated server-side allowances for shared AI spending and account concurrency."
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field :daily_limit, :integer, default: 20
    field :global_daily_limit, :integer, default: 200
    field :personal_daily_limit, :integer, default: 200
    field :max_concurrent, :integer, default: 1
    field :global_concurrent, :integer, default: 2
    field :cooldown_seconds, :integer, default: 2
  end

  @typedoc "Validated daily credit and concurrency limits."
  @type t :: %__MODULE__{}

  @doc "Constructs bounded limits; invalid values return a changeset instead of disabling enforcement."
  @spec new(map()) :: {:ok, t()} | {:error, Ecto.Changeset.t(t())}
  def new(attrs) do
    fields = [:daily_limit, :global_daily_limit, :personal_daily_limit, :max_concurrent, :global_concurrent]

    changeset =
      %__MODULE__{} |> cast(attrs, fields ++ [:cooldown_seconds]) |> validate_required(fields ++ [:cooldown_seconds])

    changeset = Enum.reduce(fields, changeset, &validate_number(&2, &1, greater_than: 0, less_than_or_equal_to: 100_000))

    changeset
    |> validate_number(:cooldown_seconds, greater_than_or_equal_to: 0, less_than_or_equal_to: 3600)
    |> apply_action(:validate)
  end
end
