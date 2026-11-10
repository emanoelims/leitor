defmodule LeitorWeb.BookAssetControllerTest do
  use LeitorWeb.ConnCase

  import Leitor.AccountsFixtures

  alias Leitor.EpubFixtures
  alias Leitor.Library
  alias Leitor.Sharing

  @png EpubFixtures.png()

  defp book_with_image(scope) do
    id = Ecto.UUID.generate(version: 7)

    asset = %{
      id: id,
      content_type: "image/png",
      byte_size: byte_size(@png),
      digest: :crypto.hash(:sha256, @png),
      data: @png
    }

    chapters = [%{id: Ecto.UUID.generate(version: 7), title: "One", depth: 0, body: "<p>Text.</p>"}]
    extracted = %{title: "Pictured", chapters: chapters, assets: [asset], cover_asset_id: id}
    {:ok, book} = Library.create_book(scope, extracted)
    {book, id, hd(chapters).id}
  end

  setup %{conn: conn} do
    scope = user_scope_fixture()
    %{conn: log_in_user(conn, scope.user), scope: scope}
  end

  describe "GET /book-assets/:id" do
    test "serves an owned image with cautious headers", %{conn: conn, scope: scope} do
      {_book, id, _chapter} = book_with_image(scope)
      conn = get(conn, ~p"/book-assets/#{id}")

      assert response(conn, 200) == @png
      assert [content_type] = get_resp_header(conn, "content-type")
      assert content_type == "image/png"
      assert get_resp_header(conn, "x-content-type-options") == ["nosniff"]
      assert get_resp_header(conn, "content-security-policy") == ["default-src 'none'; sandbox"]
      assert [cache] = get_resp_header(conn, "cache-control")
      assert cache =~ "private"
      assert get_resp_header(conn, "referrer-policy") == ["no-referrer"]
      assert get_resp_header(conn, "etag") == [~s("#{Base.encode16(:crypto.hash(:sha256, @png), case: :lower)}")]
    end

    test "does not serve another reader's image", %{conn: conn} do
      {_book, id, _chapter} = book_with_image(user_scope_fixture())
      assert conn |> get(~p"/book-assets/#{id}") |> response(404)
    end

    test "answers 404 for malformed and unknown ids", %{conn: conn} do
      assert conn |> get(~p"/book-assets/not-a-uuid") |> response(404)
      assert conn |> get(~p"/book-assets/#{Ecto.UUID.generate()}") |> response(404)
    end

    test "redirects visitors who are not signed in", %{scope: scope} do
      {_book, id, _chapter} = book_with_image(scope)
      conn = get(build_conn(), ~p"/book-assets/#{id}")
      assert redirected_to(conn) == ~p"/users/log-in"
    end
  end

  describe "GET /s/:token/book-assets/:id" do
    setup %{scope: scope} do
      {book, id, chapter} = book_with_image(scope)
      {:ok, share} = Sharing.set_link(scope, chapter, %{"link_role" => "view"})
      %{book: book, asset_id: id, chapter: chapter, share: share}
    end

    test "serves the book's image to a visitor with the link", %{share: share, asset_id: id} do
      conn = get(build_conn(), ~p"/s/#{share.token}/book-assets/#{id}")
      assert response(conn, 200) == @png
      assert get_resp_header(conn, "x-content-type-options") == ["nosniff"]
    end

    test "does not serve another book's image through the link", %{share: share} do
      {_other_book, other_id, _chapter} = book_with_image(user_scope_fixture())
      assert build_conn() |> get(~p"/s/#{share.token}/book-assets/#{other_id}") |> response(404)
    end

    test "stops serving once the link is disabled", %{scope: scope, chapter: chapter, share: share, asset_id: id} do
      {:ok, _} = Sharing.set_link(scope, chapter, %{"link_role" => "disabled"})
      assert build_conn() |> get(~p"/s/#{share.token}/book-assets/#{id}") |> response(404)
    end

    test "rejects tokens that are not valid", %{asset_id: id} do
      assert build_conn() |> get(~p"/s/short/book-assets/#{id}") |> response(404)
    end

    test "does not serve a chapter-less page's token an unrelated image", %{scope: scope, asset_id: id} do
      {:ok, page} = Leitor.Pages.create_page(scope, %{"title" => "Own page", "body" => "Text."})
      {:ok, share} = Sharing.set_link(scope, page.id, %{"link_role" => "view"})
      assert build_conn() |> get(~p"/s/#{share.token}/book-assets/#{id}") |> response(404)
    end
  end
end
