defmodule Leitor.AI.Bucket do
  @moduledoc "A locked daily accounting bucket for account and application AI credits."
  use Ecto.Schema

  @primary_key {:key, :string, autogenerate: false}
  schema "ai_usage_buckets" do
    field :used, :integer, default: 0
    field :personal_used, :integer, default: 0
    field :last_started_at, :utc_datetime
  end

  @typedoc "A daily aggregate, updated atomically while holding a database row lock."
  @type t :: %__MODULE__{}
end
