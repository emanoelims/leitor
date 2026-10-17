defmodule Leitor.Figures.Engine do
  @moduledoc "Contract for versioned, data-only figure engines. Each engine owns its schema, validation and drawing guidance."

  @callback new(map()) :: {:ok, struct()} | {:error, Ecto.Changeset.t()}
  @callback schema() :: map()
  @callback instruction() :: String.t()
end
