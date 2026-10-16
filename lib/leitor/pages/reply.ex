defmodule Leitor.Pages.Reply do
  @moduledoc "A validated follow-up question and answer stored inside its page annotation."
  use Ecto.Schema

  import Ecto.Changeset

  embedded_schema do
    field :question, :string
    field :body, :string
  end

  @typedoc "One completed exchange in an annotation's conversation."
  @type t() :: %__MODULE__{}

  @doc "Constructs a completed exchange, rejecting blank or oversized questions and answers."
  @spec new(map()) :: {:ok, t()} | {:error, Ecto.Changeset.t(t())}
  def new(attrs), do: %__MODULE__{} |> changeset(attrs) |> apply_action(:validate)

  @doc "Casts and validates the question and answer without accepting a caller-supplied identity."
  @spec changeset(t(), map()) :: Ecto.Changeset.t(t())
  def changeset(reply, attrs) do
    reply
    |> cast(attrs, [:question, :body])
    |> validate_required([:question, :body])
    |> validate_length(:question, max: 500)
    |> validate_length(:body, max: 4000)
  end
end
