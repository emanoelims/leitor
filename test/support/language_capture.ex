defmodule Leitor.LanguageCapture do
  @moduledoc false

  def generate(model, prompt, schema, options \\ []) do
    send(self(), {:language_request, model, prompt, schema})
    send(self(), {:language_options, options})
    Process.get(:language_result, {:ok, %{"answer" => "A grounded answer.", "references" => [1]}})
  end

  def stream(model, prompt, on_delta, options \\ []) do
    Enum.each(Process.get(:language_deltas, []), on_delta)
    generate(model, prompt, :text_stream, options)
  end

  def stream_object(model, prompt, schema, on_fragment, options \\ []) do
    Enum.each(Process.get(:language_fragments, []), on_fragment)
    generate(model, prompt, schema, options)
  end
end
