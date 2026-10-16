defmodule Leitor.Language.Provider do
  @moduledoc "Executes bounded ReqLLM structured and streaming requests without exposing provider credentials or errors to the UI."

  @doc "Generates and extracts a validated object; failures are mapped to recoverable categories."
  @spec generate(String.t(), String.t(), map()) :: Leitor.Language.result()
  def generate(model, prompt, schema) do
    with {:ok, resolved} <- resolve_model(model) do
      resolved
      |> ReqLLM.generate_object(prompt, schema, max_tokens: 6000, receive_timeout: 60_000)
      |> extract_object()
    end
  end

  @doc "Streams visible text deltas, then returns the complete Markdown only after a normal completion. Transport failures discard the partial result."
  @spec stream(String.t(), String.t(), Leitor.Language.text_delta_handler()) :: Leitor.Language.result()
  def stream(model, prompt, on_delta) do
    with {:ok, resolved} <- resolve_model(model),
         {:ok, response} <- start_stream(resolved, prompt) do
      response
      |> ReqLLM.StreamResponse.process_stream(on_result: on_delta)
      |> extract_text()
    end
  end

  @doc "Streams provisional JSON fragments and validates the completed object. Only content and tool argument fragments reach the callback; thinking and metadata remain private."
  @spec stream_object(String.t(), String.t(), map(), Leitor.Language.object_fragment_handler()) ::
          Leitor.Language.result()
  def stream_object(model, prompt, schema, on_fragment) do
    with {:ok, resolved} <- resolve_model(model),
         {:ok, response} <- start_object_stream(resolved, prompt, schema) do
      response
      |> ReqLLM.StreamResponse.process_stream(on_chunk: &object_fragment(&1, on_fragment))
      |> extract_stream_object()
    end
  end

  defp start_object_stream(model, prompt, schema) do
    case ReqLLM.stream_object(model, prompt, schema,
           max_tokens: 6000,
           receive_timeout: 60_000,
           total_timeout: 90_000,
           stream_idle_timeout: 30_000
         ) do
      {:ok, _} = result -> result
      {:error, _} -> {:error, :provider_error}
    end
  end

  defp object_fragment(%{type: :content, text: text}, callback) when is_binary(text), do: callback.(text)

  defp object_fragment(%{type: :meta, metadata: %{tool_call_args: %{fragment: fragment}}}, callback),
    do: callback.(fragment)

  defp object_fragment(_chunk, _callback), do: :ok

  defp extract_stream_object({:ok, %{finish_reason: reason}} = result) when reason in [:stop, :tool_calls],
    do: extract_object(result)

  defp extract_stream_object({:ok, _}), do: {:error, :invalid_response}
  defp extract_stream_object({:error, _}), do: {:error, :provider_error}

  defp start_stream(model, prompt) do
    case ReqLLM.stream_text(model, prompt,
           max_tokens: 6000,
           receive_timeout: 60_000,
           total_timeout: 90_000,
           stream_idle_timeout: 30_000
         ) do
      {:ok, _} = result -> result
      {:error, _} -> {:error, :provider_error}
    end
  end

  defp extract_text({:ok, %{finish_reason: :stop} = response}), do: {:ok, %{"markdown" => ReqLLM.Response.text(response)}}

  defp extract_text({:ok, _}), do: {:error, :invalid_response}
  defp extract_text({:error, _}), do: {:error, :provider_error}

  defp resolve_model(model) do
    if (ReqLLM.get_key(:anthropic_api_key) || System.get_env("ANTHROPIC_API_KEY")) in [nil, ""] do
      {:error, :unavailable}
    else
      case ReqLLM.model(%{provider: :anthropic, id: String.replace_prefix(model, "anthropic:", "")}) do
        {:ok, _} = resolved ->
          resolved

        {:error, _} ->
          {:error, :provider_error}
      end
    end
  end

  defp extract_object({:ok, response}) do
    case ReqLLM.Response.unwrap_object(response) do
      {:ok, object} when is_map(object) -> {:ok, Jason.decode!(Jason.encode!(object))}
      _ -> {:error, :invalid_response}
    end
  end

  defp extract_object({:error, _}), do: {:error, :provider_error}
end
