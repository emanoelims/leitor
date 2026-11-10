defmodule Leitor.Library.BookStorageTest do
  use Leitor.DataCase, async: false

  import Ecto.Query
  import Leitor.AccountsFixtures, only: [user_scope_fixture: 0]
  import Leitor.StorageFixtures

  alias Leitor.EpubFixtures
  alias Leitor.Library
  alias Leitor.Library.BookAsset
  alias Leitor.Library.Storage
  alias Leitor.Repo

  @moduletag :capture_log
  @png EpubFixtures.png()

  defp asset(id \\ Ecto.UUID.generate(version: 7), data \\ @png) do
    %{id: id, content_type: "image/png", byte_size: byte_size(data), digest: :crypto.hash(:sha256, data), data: data}
  end

  defp book(assets, chapter_title \\ "One") do
    chapters = [%{id: Ecto.UUID.generate(version: 7), title: chapter_title, depth: 0, body: "<p>Text.</p>"}]

    %{
      title: "Pictured",
      chapters: chapters,
      assets: assets,
      cover_asset_id: assets |> List.first() |> then(&(&1 && &1.id))
    }
  end

  describe "with object storage" do
    setup do
      configure_storage!()
      %{scope: user_scope_fixture(), store: start_object_store!(notify: self())}
    end

    test "stores the bytes as objects and only a key in the database", %{scope: scope, store: store} do
      %{id: id} = first = asset()
      second = asset(Ecto.UUID.generate(version: 7), @png <> "x")

      assert {:ok, %{cover_asset_id: ^id}} = Library.create_book(scope, book([first, second]))

      assert store |> objects() |> Map.keys() |> Enum.sort() ==
               Enum.sort(["book-assets/#{first.id}", "book-assets/#{second.id}"])

      assert {@png, "image/png"} = objects(store)["book-assets/#{id}"]

      assert [{nil, key}, {nil, _}] = Repo.all(from a in BookAsset, order_by: a.id, select: {a.data, a.storage_key})
      assert String.starts_with?(key, "book-assets/")
    end

    test "reads an image back from the store", %{scope: scope} do
      %{id: id} = asset = asset()
      {:ok, _} = Library.create_book(scope, book([asset]))

      assert {:ok, stored} = Library.get_book_asset(scope, id)
      assert stored.data == nil
      assert Library.asset_data(stored) == {:ok, @png}
    end

    test "never serves bytes that do not match the recorded digest", %{scope: scope, store: store} do
      %{id: id} = asset = asset()
      {:ok, _} = Library.create_book(scope, book([asset]))
      tamper!(store, "book-assets/#{id}", "<script>alert(1)</script>")

      {:ok, stored} = Library.get_book_asset(scope, id)
      assert Library.asset_data(stored) == {:error, :unavailable}
    end

    test "reports an image whose object is gone as unavailable", %{scope: scope, store: store} do
      %{id: id} = asset = asset()
      {:ok, _} = Library.create_book(scope, book([asset]))
      Agent.update(store, fn _ -> %{} end)

      {:ok, stored} = Library.get_book_asset(scope, id)
      assert Library.asset_data(stored) == {:error, :unavailable}
    end

    test "saves nothing, and removes what was uploaded, when an upload fails", %{scope: scope} do
      good = asset()
      bad = asset(Ecto.UUID.generate(version: 7), @png <> "y")
      bad_key = "book-assets/#{bad.id}"
      store = start_object_store!(fail: fn {method, key} -> if method == "PUT" and key == bad_key, do: 503 end)

      assert Library.create_book(scope, book([good, bad])) == {:error, :storage_unavailable}
      assert objects(store) == %{}
      assert Library.list_books(scope) == []
      assert Repo.aggregate(BookAsset, :count) == 0
    end

    test "removes the uploaded objects when the book itself is invalid", %{scope: scope, store: store} do
      extracted = book([asset()], String.duplicate("t", 300))

      assert {:error, %Ecto.Changeset{}} = Library.create_book(scope, extracted)
      assert objects(store) == %{}
    end

    test "delete_book/2 removes the objects too", %{scope: scope, store: store} do
      {:ok, created} = Library.create_book(scope, book([asset()]))
      assert map_size(objects(store)) == 1

      assert {:ok, _} = Library.delete_book(scope, created)
      assert objects(store) == %{}
    end

    test "delete_book/2 still deletes when the store is down", %{scope: scope} do
      {:ok, created} = Library.create_book(scope, book([asset()]))
      start_object_store!(fail: fn _ -> 500 end)

      assert {:ok, _} = Library.delete_book(scope, created)
      assert Library.list_books(scope) == []
    end

    test "keeps serving images saved before storage was configured", %{scope: scope} do
      Application.put_env(:leitor, Storage, req_options: [plug: {Req.Test, Storage}, retry: false])
      %{id: id} = legacy = asset()
      {:ok, _} = Library.create_book(scope, book([legacy]))
      configure_storage!()

      {:ok, stored} = Library.get_book_asset(scope, id)
      assert Library.asset_data(stored) == {:ok, @png}
    end
  end

  describe "without object storage" do
    test "keeps the bytes in the database and serves them from there" do
      scope = user_scope_fixture()
      %{id: id} = asset = asset()

      assert {:ok, _} = Library.create_book(scope, book([asset]))
      assert [{@png, nil}] = Repo.all(from a in BookAsset, select: {a.data, a.storage_key})
      assert {:ok, stored} = Library.get_book_asset(scope, id)
      assert Library.asset_data(stored) == {:ok, @png}
    end
  end

  test "the database requires exactly one place for an image's bytes" do
    scope = user_scope_fixture()
    {:ok, book} = Library.create_book(scope, book([]))

    row = %{
      id: Ecto.UUID.generate(),
      book_id: book.id,
      content_type: "image/png",
      byte_size: 1,
      digest: "d",
      inserted_at: DateTime.utc_now(:second)
    }

    assert_raise Postgrex.Error, ~r/book_assets_one_location/, fn -> Repo.insert_all(BookAsset, [row]) end

    assert_raise Postgrex.Error, ~r/book_assets_one_location/, fn ->
      Repo.insert_all(BookAsset, [Map.merge(row, %{data: "x", storage_key: "k"})])
    end
  end
end
