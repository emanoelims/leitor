defmodule Leitor.StorageFixtures do
  @moduledoc """
  Test helpers for object storage: a configured bucket and an in-memory object store behind `Req.Test`.

  Tests using these helpers change application configuration, so they must not be `async`.
  """
  import ExUnit.Callbacks, only: [on_exit: 1, start_supervised!: 1]

  alias Leitor.Library.Storage

  @bucket "test-bucket"

  @doc "Configures a bucket and fake credentials for the current test, restoring the configuration afterwards."
  @spec configure_storage!() :: :ok
  def configure_storage! do
    previous = Application.get_env(:leitor, Storage, [])

    Application.put_env(
      :leitor,
      Storage,
      Keyword.merge(previous,
        bucket: @bucket,
        access_key_id: "AKIATESTKEY",
        secret_access_key: "test-secret-key",
        endpoint: "https://storage.test"
      )
    )

    on_exit(fn -> Application.put_env(:leitor, Storage, previous) end)
  end

  @doc """
  Starts an in-memory object store answering `PUT`, `GET` and `DELETE` for the configured bucket.

  Options: `:fail` is a function from `{method, key}` to a status code that makes that request fail, and
  `:notify` is a pid that receives `{:object_request, method, key}` for every request.
  Returns the store, readable with `objects/1`. Starting another store in the same test replaces the first.
  """
  @spec start_object_store!(keyword()) :: pid()
  def start_object_store!(opts \\ []) do
    store = start_supervised!(Supervisor.child_spec({Agent, fn -> %{} end}, id: make_ref()))
    fail = Keyword.get(opts, :fail, fn _request -> nil end)
    notify = Keyword.get(opts, :notify)
    prefix = "/#{@bucket}/"

    Req.Test.stub(Storage, fn conn ->
      key = String.replace_prefix(conn.request_path, prefix, "")
      if notify, do: send(notify, {:object_request, conn.method, key})

      case fail.({conn.method, key}) do
        nil -> respond(conn, store, key)
        status -> Plug.Conn.send_resp(conn, status, "")
      end
    end)

    store
  end

  @doc "Returns the stored objects as a map from key to `{bytes, content_type}`."
  @spec objects(pid()) :: %{String.t() => {binary(), String.t()}}
  def objects(store), do: Agent.get(store, & &1)

  @doc "Replaces the bytes of a stored object, as a corrupted store would."
  @spec tamper!(pid(), String.t(), binary()) :: :ok
  def tamper!(store, key, bytes),
    do: Agent.update(store, fn objects -> Map.update!(objects, key, fn {_, type} -> {bytes, type} end) end)

  defp respond(%{method: "PUT"} = conn, store, key) do
    {:ok, body, conn} = Plug.Conn.read_body(conn, length: 20_000_000)
    type = conn |> Plug.Conn.get_req_header("content-type") |> List.first()
    Agent.update(store, &Map.put(&1, key, {body, type}))
    Plug.Conn.send_resp(conn, 200, "")
  end

  defp respond(%{method: "GET"} = conn, store, key) do
    case Agent.get(store, &Map.get(&1, key)) do
      nil -> Plug.Conn.send_resp(conn, 404, "")
      {body, type} -> conn |> Plug.Conn.put_resp_content_type(type, nil) |> Plug.Conn.send_resp(200, body)
    end
  end

  defp respond(%{method: "DELETE"} = conn, store, key) do
    Agent.update(store, &Map.delete(&1, key))
    Plug.Conn.send_resp(conn, 204, "")
  end
end
