defmodule Leitor.LanguageGate do
  @moduledoc false

  def generate(model, prompt, _schema, _options \\ []) do
    send(Application.fetch_env!(:leitor, :language_test_owner), {:language_settings, model, prompt})
    send(Application.fetch_env!(:leitor, :language_test_owner), {:language_started, self()})

    receive do
      {:complete, response} -> response
    end
  end

  def stream(model, prompt, on_delta, _options \\ []) do
    send(Application.fetch_env!(:leitor, :language_test_owner), {:language_settings, model, prompt})
    send(Application.fetch_env!(:leitor, :language_test_owner), {:language_started, self()})
    stream_reply(on_delta)
  end

  def stream_object(model, prompt, _schema, on_fragment, _options \\ []), do: stream(model, prompt, on_fragment)

  defp stream_reply(on_delta) do
    receive do
      {:delta, text} ->
        result = on_delta.(text)
        send(Application.fetch_env!(:leitor, :language_test_owner), {:language_delta, result})
        stream_reply(on_delta)

      {:complete, response} ->
        response
    end
  end
end
