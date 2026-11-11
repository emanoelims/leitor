defmodule Leitor.Library.StorageTest do
  use ExUnit.Case, async: false

  import Leitor.StorageFixtures

  alias Leitor.Library.Storage

  @moduletag :capture_log

  describe "without a bucket" do
    test "is not configured and refuses to store" do
      refute Storage.configured?()
      assert Storage.put("a", "bytes", "image/png") == {:error, :not_configured}
      assert Storage.get("a") == {:error, :not_configured}
    end

    test "needs a bucket and both credentials" do
      previous = Application.get_env(:leitor, Storage)
      on_exit(fn -> Application.put_env(:leitor, Storage, previous) end)

      Application.put_env(:leitor, Storage, Keyword.merge(previous, bucket: "b", access_key_id: "k"))
      refute Storage.configured?()
    end
  end

  describe "with a bucket" do
    setup do
      configure_storage!()
      :ok
    end

    test "signs requests with AWS Signature V4 without exposing the secret" do
      test = self()

      Req.Test.stub(Storage, fn conn ->
        send(test, {:request, conn.method, conn.request_path, Map.new(conn.req_headers), conn})
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        send(test, {:body, body})
        Plug.Conn.send_resp(conn, 200, "")
      end)

      assert Storage.put("book-assets/abc", "image-bytes", "image/png") == :ok

      assert_receive {:request, "PUT", "/test-bucket/book-assets/abc", headers, _conn}
      assert_receive {:body, "image-bytes"}
      assert headers["authorization"] =~ ~r|^AWS4-HMAC-SHA256 Credential=AKIATESTKEY/\d{8}/auto/s3/aws4_request|
      assert headers["x-amz-content-sha256"] == Base.encode16(:crypto.hash(:sha256, "image-bytes"), case: :lower)
      assert headers["content-type"] == "image/png"
      refute inspect(headers) =~ "test-secret-key"
    end

    test "stores, reads and removes an object" do
      store = start_object_store!()

      assert Storage.put("book-assets/abc", "bytes", "image/png") == :ok
      assert objects(store) == %{"book-assets/abc" => {"bytes", "image/png"}}
      assert Storage.get("book-assets/abc") == {:ok, "bytes"}
      assert Storage.delete("book-assets/abc") == :ok
      assert Storage.get("book-assets/abc") == {:error, :not_found}
    end

    test "treats removing a missing object as done" do
      start_object_store!()
      assert Storage.delete("book-assets/never-existed") == :ok
    end

    test "reports failures instead of raising" do
      start_object_store!(fail: fn _ -> 503 end)

      assert Storage.put("a", "bytes", "image/png") == {:error, {:status, 503}}
      assert Storage.get("a") == {:error, {:status, 503}}
      assert Storage.delete("a") == {:error, {:status, 503}}
    end

    test "reports network errors" do
      Req.Test.stub(Storage, &Req.Test.transport_error(&1, :econnrefused))

      assert {:error, %Req.TransportError{reason: :econnrefused}} = Storage.get("a")
    end

    test "delete_all keeps going after a failure" do
      start_object_store!(notify: self(), fail: fn {_method, key} -> if key == "b", do: 500 end)

      assert Storage.delete_all(["a", "b", "c"]) == :ok
      assert_receive {:object_request, "DELETE", "a"}
      assert_receive {:object_request, "DELETE", "b"}
      assert_receive {:object_request, "DELETE", "c"}
    end

    test "uses the configured endpoint and region" do
      previous = Application.get_env(:leitor, Storage)
      on_exit(fn -> Application.put_env(:leitor, Storage, previous) end)
      Application.put_env(:leitor, Storage, Keyword.merge(previous, endpoint: "https://other.test/", region: "eu-1"))
      test = self()

      Req.Test.stub(Storage, fn conn ->
        send(test, {:host, conn.host, Plug.Conn.get_req_header(conn, "authorization")})
        Plug.Conn.send_resp(conn, 200, "")
      end)

      assert Storage.put("a", "bytes", "image/png") == :ok
      assert_receive {:host, "other.test", [authorization]}
      assert authorization =~ "/eu-1/s3/aws4_request"
    end
  end
end
