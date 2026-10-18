defmodule Leitor.Figures.Review do
  @moduledoc "A validated independent review. Contradictory prose blocks publication even when visual acceptance is claimed."
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field :accept, :boolean
    field :critique, :string
    field :explanation_consistent, :boolean
    field :explanation_evidence, :string
  end

  @typedoc "A bounded review with explicit evidence for explanation/model consistency."
  @type t :: %__MODULE__{}

  @doc "Validates provider decisions and forces rejection for an explanation conflict. Missing evidence cannot grant acceptance."
  @spec new(map()) :: {:ok, t()} | {:error, Ecto.Changeset.t(t())}
  def new(attrs) do
    fields = [:accept, :critique, :explanation_consistent, :explanation_evidence]

    changeset =
      %__MODULE__{}
      |> cast(attrs, fields)
      |> validate_required(fields)
      |> validate_length(:critique, max: 8000)
      |> validate_length(:explanation_evidence, max: 2000)

    with {:ok, review} <- apply_action(changeset, :validate) do
      if review.explanation_consistent,
        do: {:ok, review},
        else:
          {:ok,
           %{
             review
             | accept: false,
               critique: review.critique <> "\nExplanation conflict: " <> review.explanation_evidence
           }}
    end
  end
end
