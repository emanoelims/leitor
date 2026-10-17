defmodule Leitor.Language.Provider do
  @moduledoc "Executes bounded ReqLLM structured and streaming requests without exposing provider credentials or errors to the UI."

  alias ReqLLM.Message.ContentPart

  require Logger

  @doc "Generates and extracts a validated object; failures are mapped to recoverable categories."
  @spec generate(String.t(), String.t(), map()) :: Leitor.Language.result()
  @spec generate(String.t(), String.t(), map(), keyword()) :: Leitor.Language.result()
  def generate(model, prompt, schema, options \\ []) do
    {usage_callback, options} = Keyword.pop(options, :usage_callback, fn _usage -> :ok end)

    with {:ok, resolved} <- resolve_model(model, options) do
      resolved
      |> ReqLLM.generate_object(prompt, schema, Keyword.merge([max_tokens: 6000, receive_timeout: 60_000], options))
      |> notify_usage(usage_callback)
      |> extract_object()
    end
  end

  @doc "Reviews isolated figure screenshots with bounded source and test evidence. Images contain only the generated figure."
  @spec review(String.t(), String.t(), [binary()], map(), keyword()) :: Leitor.Language.result()
  def review(model, prompt, images, schema, options) do
    {usage_callback, options} = Keyword.pop(options, :usage_callback, fn _usage -> :ok end)
    parts = [ContentPart.text(prompt) | Enum.map(images, &ContentPart.image/1)]
    context = ReqLLM.context(ReqLLM.Context.user(parts))

    with {:ok, resolved} <- resolve_model(model, options) do
      resolved
      |> ReqLLM.generate_object(context, schema, options)
      |> notify_usage(usage_callback)
      |> extract_object()
    end
  end

  @doc "Requests one native coding-tool turn. Tool callbacks are never executed by this function; the isolated figure editor handles them explicitly."
  @spec code_step(String.t(), ReqLLM.Context.t(), [ReqLLM.Tool.t()], keyword()) ::
          {:ok, ReqLLM.Response.t()} | {:error, :unavailable | :provider_error}
  def code_step(model, context, tools, options) do
    {usage_callback, options} = Keyword.pop(options, :usage_callback, fn _usage -> :ok end)

    with {:ok, resolved} <- resolve_model(model, options) do
      case resolved
           |> ReqLLM.generate_text(context, Keyword.put(options, :tools, tools))
           |> notify_usage(usage_callback) do
        {:ok, _response} = result -> result
        {:error, error} -> provider_error(error)
      end
    end
  end

  @doc "Streams visible text deltas, then returns the complete Markdown only after a normal completion. Transport failures discard the partial result."
  @spec stream(String.t(), ReqLLM.Context.prompt(), Leitor.Language.text_delta_handler()) :: Leitor.Language.result()
  @spec stream(String.t(), ReqLLM.Context.prompt(), Leitor.Language.text_delta_handler(), keyword()) ::
          Leitor.Language.result()
  def stream(model, prompt, on_delta, options \\ []) do
    {usage_callback, options} = Keyword.pop(options, :usage_callback, fn _usage -> :ok end)

    with {:ok, resolved} <- resolve_model(model, options),
         {:ok, response} <- start_stream(resolved, prompt, options) do
      response
      |> ReqLLM.StreamResponse.process_stream(on_result: on_delta)
      |> notify_usage(usage_callback)
      |> extract_text()
    end
  end

  @doc "Streams authored code while showing the model the previous isolated figure captures."
  @spec stream_visual(String.t(), String.t(), [binary()], Leitor.Language.text_delta_handler(), keyword()) ::
          Leitor.Language.result()
  def stream_visual(model, prompt, images, on_delta, options) do
    parts = [ContentPart.text(prompt) | Enum.map(images, &ContentPart.image/1)]
    stream(model, ReqLLM.context(ReqLLM.Context.user(parts)), on_delta, options)
  end

  @doc "Streams provisional JSON fragments and validates the completed object. Only content and tool argument fragments reach the callback; thinking and metadata remain private."
  @spec stream_object(String.t(), String.t(), map(), Leitor.Language.object_fragment_handler()) ::
          Leitor.Language.result()
  @spec stream_object(String.t(), String.t(), map(), Leitor.Language.object_fragment_handler(), keyword()) ::
          Leitor.Language.result()
  def stream_object(model, prompt, schema, on_fragment, options \\ []) do
    {usage_callback, options} = Keyword.pop(options, :usage_callback, fn _usage -> :ok end)

    with {:ok, resolved} <- resolve_model(model, options),
         {:ok, response} <- start_object_stream(resolved, prompt, schema, options) do
      response
      |> ReqLLM.StreamResponse.process_stream(on_chunk: &object_fragment(&1, on_fragment))
      |> notify_usage(usage_callback)
      |> extract_stream_object()
    end
  end

  defp notify_usage({:ok, response} = result, callback) do
    callback.(response.usage || %{})
    result
  end

  defp notify_usage(result, callback) do
    callback.(%{})
    result
  end

  defp start_object_stream(model, prompt, schema, options) do
    case ReqLLM.stream_object(
           model,
           prompt,
           schema,
           Keyword.merge(
             [
               max_tokens: 6000,
               receive_timeout: 60_000,
               total_timeout: 90_000,
               stream_idle_timeout: 30_000
             ],
             options
           )
         ) do
      {:ok, _} = result -> result
      {:error, error} -> provider_error(error)
    end
  end

  defp object_fragment(%{type: :content, text: text}, callback) when is_binary(text), do: callback.(text)

  defp object_fragment(%{type: :meta, metadata: %{tool_call_args: %{fragment: fragment}}}, callback),
    do: callback.(fragment)

  defp object_fragment(_chunk, _callback), do: :ok

  defp extract_stream_object({:ok, %{finish_reason: reason}} = result) when reason in [:stop, :tool_calls],
    do: extract_object(result)

  defp extract_stream_object({:ok, response}) do
    Logger.warning(
      "Structured stream ended without completion: #{inspect(response.finish_reason)}, " <>
        "#{ReqLLM.Response.reasoning_tokens(response)} reasoning tokens, #{byte_size(ReqLLM.Response.text(response) || "")} visible bytes"
    )

    {:error, :invalid_response}
  end

  defp extract_stream_object({:error, error}), do: provider_error(error)

  defp start_stream(model, prompt, options) do
    case ReqLLM.stream_text(
           model,
           prompt,
           Keyword.merge(
             [
               max_tokens: 6000,
               receive_timeout: 60_000,
               total_timeout: 90_000,
               stream_idle_timeout: 30_000
             ],
             options
           )
         ) do
      {:ok, _} = result -> result
      {:error, error} -> provider_error(error)
    end
  end

  defp extract_text({:ok, %{finish_reason: :stop} = response}), do: {:ok, %{"markdown" => ReqLLM.Response.text(response)}}

  defp extract_text({:ok, response}) do
    Logger.warning(
      "Language text stream ended without completion: #{inspect(response.finish_reason)}, " <>
        "#{ReqLLM.Response.reasoning_tokens(response)} reasoning tokens, " <>
        "#{byte_size(ReqLLM.Response.text(response) || "")} visible bytes"
    )

    {:error, :invalid_response}
  end

  defp extract_text({:error, error}), do: provider_error(error)

  defp resolve_model(model, options) do
    if Keyword.get(options, :api_key, ReqLLM.get_key(:anthropic_api_key) || System.get_env("ANTHROPIC_API_KEY")) in [
         nil,
         ""
       ] do
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
      {:ok, object} when is_map(object) ->
        {:ok, Jason.decode!(Jason.encode!(object))}

      _ ->
        Logger.warning("Language provider returned no validated object: #{inspect(response.finish_reason)}")
        {:error, :invalid_response}
    end
  end

  defp extract_object({:error, error}), do: provider_error(error)

  defp provider_error(error) do
    {kind, status} =
      case error do
        %{__struct__: module, status: status} when is_integer(status) -> {module, status}
        %{__struct__: module} -> {module, nil}
        _ -> {:unknown, nil}
      end

    Logger.warning(
      "Language provider request failed: #{inspect(kind)}, HTTP #{inspect(status)}, class #{stream_failure_class(error)}"
    )

    {:error, :provider_error}
  end

  defp stream_failure_class(%{cause: %{kind: kind}}) when is_atom(kind), do: Atom.to_string(kind)
  defp stream_failure_class(%{reason: reason}) when is_atom(reason), do: Atom.to_string(reason)

  defp stream_failure_class(%{reason: reason}) when is_binary(reason) do
    Enum.find(
      ~w(timeout idle closed cancel overload schema decode context buffer terminated),
      "unspecified",
      &String.contains?(String.downcase(reason), &1)
    )
  end

  defp stream_failure_class(_), do: "unspecified"
end
