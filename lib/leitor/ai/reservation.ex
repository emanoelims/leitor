defmodule Leitor.AI.Reservation do
  @moduledoc "An account-owned, expiring AI concurrency lease. Attempts consume credits even if canceled."
  use Ecto.Schema

  @primary_key {:id, Ecto.UUID, autogenerate: [version: 7]}
  @foreign_key_type :binary_id
  schema "ai_reservations" do
    field :operation, :string
    field :mode, :string
    field :credits, :integer
    field :model, :string
    field :outcome, :string
    field :input_tokens, :integer, default: 0
    field :output_tokens, :integer, default: 0
    field :cache_read_tokens, :integer, default: 0
    field :cache_write_tokens, :integer, default: 0
    field :estimated_cost_micros, :integer, default: 0
    field :measured_calls, :integer, default: 0
    field :unmeasured_calls, :integer, default: 0
    field :expires_at, :utc_datetime
    field :finished_at, :utc_datetime
    belongs_to :user, Leitor.Accounts.User
    timestamps(type: :utc_datetime, updated_at: false)
  end

  @typedoc "A lease that stops blocking concurrency after completion or expiry."
  @type t :: %__MODULE__{}
end
