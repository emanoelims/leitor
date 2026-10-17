defmodule Leitor.AI.Client do
  @moduledoc "A short-lived authorized AI execution. Credentials are redacted and never assigned to a LiveView."
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field :lease_id, Ecto.UUID
    field :model, :string
    field :mode, :string
    field :timeout_ms, :integer, default: 90_000
    field :max_tokens, :integer
    field :api_key, :string, redact: true
  end

  @typedoc "An authorized request with a bounded output and a private provider credential."
  @type t :: %__MODULE__{}

  @doc "Validates an internal authorization assembled from scoped credentials and server policy."
  @spec new(map()) :: {:ok, t()} | {:error, Ecto.Changeset.t(t())}
  def new(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:lease_id, :model, :mode, :max_tokens, :timeout_ms, :api_key])
    |> validate_required([:lease_id, :model, :mode, :max_tokens, :timeout_ms])
    |> validate_inclusion(:mode, ~w(shared personal))
    |> validate_key_mode()
    |> validate_number(:max_tokens, greater_than: 0, less_than_or_equal_to: 65_536)
    |> validate_number(:timeout_ms, greater_than_or_equal_to: 90_000, less_than_or_equal_to: 1_200_000)
    |> validate_shared_timeout()
    |> apply_action(:validate)
  end

  defp validate_shared_timeout(changeset) do
    if get_field(changeset, :mode) == "shared",
      do: validate_number(changeset, :timeout_ms, less_than_or_equal_to: 90_000),
      else: changeset
  end

  defp validate_key_mode(changeset) do
    case get_field(changeset, :mode) do
      "personal" ->
        validate_required(changeset, [:api_key])

      "shared" ->
        if get_field(changeset, :api_key),
          do: add_error(changeset, :api_key, "must be absent for shared execution"),
          else: changeset

      _ ->
        changeset
    end
  end

  @doc "Returns request-local provider options; these must not be logged or sent to the browser."
  @spec options(t()) :: keyword()
  def options(client) do
    options = [model: client.model, max_tokens: client.max_tokens, total_timeout: client.timeout_ms]
    options = if client.max_tokens > 6000, do: Keyword.put(options, :reasoning_effort, :low), else: options
    if client.api_key, do: Keyword.put(options, :api_key, client.api_key), else: options
  end
end
