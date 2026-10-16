defmodule Leitor.LanguageCapture do
  @moduledoc false

  def generate(model, prompt, schema) do
    send(self(), {:language_request, model, prompt, schema})
    Process.get(:language_result, {:ok, %{"answer" => "A grounded answer.", "references" => [1]}})
  end

  def stream(model, prompt, on_delta) do
    Enum.each(Process.get(:language_deltas, []), on_delta)
    generate(model, prompt, :text_stream)
  end

  def stream_object(model, prompt, schema, on_fragment) do
    Enum.each(Process.get(:language_fragments, []), on_fragment)
    generate(model, prompt, schema)
  end
end
