defmodule Leitor.Library.Storage do
  @moduledoc """
  Object storage for book images, spoken to over the S3 API with `Req` and AWS Signature V4. It is meant for
  Tigris (`fly storage create`) and works with any S3-compatible service.

  Storage is optional. Without a bucket and credentials `configured?/0` is `false` and images stay in the
  database, which is what development and tests use. Configuration is read when needed:

      config :leitor, Leitor.Library.Storage,
        bucket: "leitor-books",
        access_key_id: "...",
        secret_access_key: "...",
        endpoint: "https://t3.storage.dev",
        region: "auto"

  `:req_options` is merged into every request; tests use it to route requests to `Req.Test`.
  """
  require Logger

  @default_endpoint "https://t3.storage.dev"
  @default_region "auto"

  @typedoc "The name of an object inside the bucket."
  @type key() :: String.t()

  @doc "Whether a bucket and credentials are configured."
  @spec configured?() :: boolean()
  def configured?, do: match?({:ok, _}, settings())

  @doc "Stores `data` under `key` with the given content type."
  @spec put(key(), binary(), String.t()) :: :ok | {:error, term()}
  def put(key, data, content_type) when is_binary(data) do
    case request(:put, key, body: data, headers: [{"content-type", content_type}]) do
      {:ok, %{status: status}} when status in 200..299 -> :ok
      other -> failure(:put, key, other)
    end
  end

  @doc "Fetches the object stored under `key`."
  @spec get(key()) :: {:ok, binary()} | {:error, :not_found | term()}
  def get(key) do
    case request(:get, key, []) do
      {:ok, %{status: 200, body: body}} when is_binary(body) -> {:ok, body}
      {:ok, %{status: 404}} -> {:error, :not_found}
      other -> failure(:get, key, other)
    end
  end

  @doc "Removes the object stored under `key`. An object that is already gone counts as removed."
  @spec delete(key()) :: :ok | {:error, term()}
  def delete(key) do
    case request(:delete, key, []) do
      {:ok, %{status: status}} when status in [200, 202, 204, 404] -> :ok
      other -> failure(:delete, key, other)
    end
  end

  @doc """
  Removes many objects, never raising. A failure is logged and the remaining objects are still removed, so
  at worst an unreferenced object stays behind.
  """
  @spec delete_all([key()]) :: :ok
  def delete_all(keys) do
    Enum.each(keys, &delete/1)
  end

  defp request(method, key, options) do
    with {:ok, settings} <- settings() do
      [
        method: method,
        url: "#{settings.endpoint}/#{settings.bucket}/#{URI.encode(key)}",
        aws_sigv4: [
          access_key_id: settings.access_key_id,
          secret_access_key: settings.secret_access_key,
          service: :s3,
          region: settings.region
        ],
        decode_body: false,
        retry: :transient,
        max_retries: 2
      ]
      |> Keyword.merge(options)
      |> Req.request(settings.req_options)
    end
  end

  defp settings do
    config = Application.get_env(:leitor, __MODULE__, [])

    with bucket when is_binary(bucket) <- config[:bucket],
         access_key_id when is_binary(access_key_id) <- config[:access_key_id],
         secret_access_key when is_binary(secret_access_key) <- config[:secret_access_key] do
      {:ok,
       %{
         bucket: bucket,
         access_key_id: access_key_id,
         secret_access_key: secret_access_key,
         endpoint: String.trim_trailing(config[:endpoint] || @default_endpoint, "/"),
         region: config[:region] || @default_region,
         req_options: config[:req_options] || []
       }}
    else
      _ -> {:error, :not_configured}
    end
  end

  # Credentials are never part of the message; only the operation, object and outcome are logged.
  defp failure(method, key, {:ok, %{status: status}}) do
    Logger.warning("Object storage #{method} #{key} answered #{status}")
    {:error, {:status, status}}
  end

  defp failure(method, key, {:error, reason}) do
    Logger.warning("Object storage #{method} #{key} failed: #{inspect(reason)}")
    {:error, reason}
  end
end
