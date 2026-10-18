defmodule Leitor.FigureProgramStreamStub do
  @moduledoc false
  def stream_object(_model, _prompt, _schema, callback, _options) do
    callback.("{\"figure\":\"unfinished")
    {:error, :provider_error}
  end
end
