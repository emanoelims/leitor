defmodule Leitor.Figures.RemoteRunner do
  @moduledoc "Authenticated transport to the private isolated checker. Provider credentials never enter this protocol."

  @doc "Submits bounded files and polls within one 100-second deadline. Only an explicit pre-admission 429 busy response may wait and resubmit; redirects, transport failures and uncertain admissions are never retried."
  @spec check(map(), keyword()) :: {:ok, map()} | {:error, :runner_unavailable | :runner_timeout | :invalid_response}
  def check(program, config) do
    request =
      Req.new(
        [
          base_url: Keyword.fetch!(config, :url),
          auth: {:bearer, Keyword.fetch!(config, :token)},
          retry: false,
          redirect: false,
          inet6: true,
          receive_timeout: 10_000
        ] ++ Keyword.get(config, :request_options, [])
      )

    deadline = System.monotonic_time(:millisecond) + 100_000
    submit(request, program, deadline, config)
  end

  defp submit(request, program, deadline, config) do
    if System.monotonic_time(:millisecond) >= deadline do
      {:error, :runner_timeout}
    else
      case Req.post(request, url: "/checks", json: program) do
        {:ok, %{status: 202, body: %{"id" => id}}} ->
          poll_accepted(request, id, deadline, config)

        {:ok, %{status: 429, body: %{"error" => "busy"}}} ->
          Process.sleep(Keyword.get(config, :poll_interval, 500))
          submit(request, program, deadline, config)

        _ ->
          {:error, :runner_unavailable}
      end
    end
  end

  defp poll_accepted(request, id, deadline, config) do
    case Ecto.UUID.cast(id) do
      {:ok, id} -> poll(request, id, deadline, config)
      :error -> {:error, :invalid_response}
    end
  end

  defp poll(request, id, deadline, config) do
    if System.monotonic_time(:millisecond) >= deadline do
      {:error, :runner_timeout}
    else
      case Req.get(request, url: "/checks/#{id}") do
        {:ok, %{status: 202}} ->
          Process.sleep(Keyword.get(config, :poll_interval, 500))
          poll(request, id, deadline, config)

        {:ok, %{status: 200, body: body}} ->
          decode(body)

        _ ->
          {:error, :runner_unavailable}
      end
    end
  end

  defp decode(%{"report" => %{"ok" => ok, "images" => names} = report, "images" => encoded} = body)
       when is_boolean(ok) and is_list(names) and is_list(encoded) and length(names) == length(encoded) and
              length(names) <= 6 do
    allowed = ~w(light.png tested.png detail.png interaction.png dark.png mobile.png)
    images = Enum.map(encoded, &decode_image/1)

    valid =
      Enum.all?(names, &(&1 in allowed)) and Enum.uniq(names) == names and
        byte_size(Jason.encode!(report)) <= 50_000 and Enum.all?(images, &is_binary/1)

    if valid, do: complete(body, %{report: report, images: images}), else: {:error, :invalid_response}
  end

  defp decode(_), do: {:error, :invalid_response}

  defp decode_image(encoded) when is_binary(encoded) and byte_size(encoded) <= 2_666_668 do
    case Base.decode64(encoded) do
      {:ok, <<137, 80, 78, 71, _::binary>> = png} when byte_size(png) <= 2_000_000 -> png
      _ -> nil
    end
  end

  defp decode_image(_), do: nil

  defp complete(_body, %{report: %{"ok" => false}} = result), do: {:ok, result}
  defp complete(_body, %{report: %{"ok" => true, "model_only" => true}, images: []} = result), do: {:ok, result}

  defp complete(%{"bundle" => bundle, "style" => style}, %{images: [_ | _]} = result)
       when is_binary(bundle) and byte_size(bundle) <= 1_000_000 and is_binary(style) and byte_size(style) <= 100_000,
       do: {:ok, Map.merge(result, %{bundle: bundle, style: style})}

  defp complete(_body, _result), do: {:error, :invalid_response}
end
