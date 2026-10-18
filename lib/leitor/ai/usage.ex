defmodule Leitor.AI.Usage do
  @moduledoc "Validated provider counters and a dated, standard-routing Claude cost estimate. Missing usage is never represented as a measured zero."
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field :input_tokens, :integer
    field :output_tokens, :integer
    field :cache_read_tokens, :integer, default: 0
    field :cache_write_tokens, :integer, default: 0
    field :input_includes_cached, :boolean, default: false
    field :billing_usage_complete, :boolean, default: true
  end

  @typedoc "A measured response, with provider-native cache counters kept separate."
  @type t :: %__MODULE__{}

  @doc "Validates canonical ReqLLM usage. Absent input/output counters and inconsistent cache totals are unmeasured."
  @spec new(map()) :: {:ok, t()} | {:error, Ecto.Changeset.t(t())}
  def new(attrs) do
    fields = [:input_tokens, :output_tokens, :cache_read_tokens, :cache_write_tokens]

    changeset =
      %__MODULE__{}
      |> cast(attrs, fields ++ [:input_includes_cached, :billing_usage_complete])
      |> validate_required(fields)
      |> validate_inclusion(:billing_usage_complete, [true])

    changeset =
      Enum.reduce(fields, changeset, &validate_number(&2, &1, greater_than_or_equal_to: 0, less_than: 1_000_000_000))

    changeset =
      if get_field(changeset, :input_includes_cached) do
        validate_number(changeset, :input_tokens,
          greater_than_or_equal_to:
            (get_field(changeset, :cache_read_tokens) || 0) + (get_field(changeset, :cache_write_tokens) || 0)
        )
      else
        changeset
      end

    apply_action(changeset, :validate)
  end

  @doc "Estimates USD microdollars at published 2026-10-17 rates. Cache writes conservatively use the one-hour rate; reasoning is already part of output. Unknown models return nil."
  @spec estimate(t(), String.t() | nil) :: non_neg_integer() | nil
  def estimate(usage, model) do
    prompt =
      usage.input_tokens +
        if(usage.input_includes_cached, do: 0, else: usage.cache_read_tokens + usage.cache_write_tokens)

    rates =
      case model do
        "anthropic:claude-opus-5-5" -> {4000, 20_000, 200}
        "anthropic:claude-sonnet-5-5" -> {2000, 10_000, 100}
        "anthropic:claude-haiku-5-5" when prompt > 100_000 -> {500, 2500, 50}
        "anthropic:claude-haiku-5-5" -> {100, 500, 10}
        _ -> nil
      end

    if rates do
      {input_rate, output_rate, read_rate} = rates

      uncached =
        usage.input_tokens -
          if(usage.input_includes_cached, do: usage.cache_read_tokens + usage.cache_write_tokens, else: 0)

      nanos =
        uncached * input_rate + usage.output_tokens * output_rate + usage.cache_read_tokens * read_rate +
          usage.cache_write_tokens * input_rate * 2

      div(nanos + 999, 1000)
    end
  end
end
