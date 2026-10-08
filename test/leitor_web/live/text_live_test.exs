defmodule LeitorWeb.TextLiveTest do
  use LeitorWeb.ConnCase

  import Leitor.LibraryFixtures
  import Phoenix.LiveViewTest

  @create_attrs %{position: 42, title: "some title", source: "some source", body: "some body"}
  @update_attrs %{position: 43, title: "some updated title", source: "some updated source", body: "some updated body"}
  @invalid_attrs %{position: nil, title: nil, source: nil, body: nil}

  setup :register_and_log_in_user

  defp create_text(%{scope: scope}) do
    text = text_fixture(scope)

    %{text: text}
  end

  describe "Index" do
    setup [:create_text]

    test "lists all texts", %{conn: conn, text: text} do
      {:ok, _index_live, html} = live(conn, ~p"/texts")

      assert html =~ "Listing Texts"
      assert html =~ text.title
    end

    test "saves new text", %{conn: conn} do
      {:ok, index_live, _html} = live(conn, ~p"/texts")

      assert {:ok, form_live, _} =
               index_live
               |> element("a", "New Text")
               |> render_click()
               |> follow_redirect(conn, ~p"/texts/new")

      assert render(form_live) =~ "New Text"

      assert form_live
             |> form("#text-form", text: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert {:ok, index_live, _html} =
               form_live
               |> form("#text-form", text: @create_attrs)
               |> render_submit()
               |> follow_redirect(conn, ~p"/texts")

      html = render(index_live)
      assert html =~ "Text created successfully"
      assert html =~ "some title"
    end

    test "updates text in listing", %{conn: conn, text: text} do
      {:ok, index_live, _html} = live(conn, ~p"/texts")

      assert {:ok, form_live, _html} =
               index_live
               |> element("#texts-#{text.id} a", "Edit")
               |> render_click()
               |> follow_redirect(conn, ~p"/texts/#{text}/edit")

      assert render(form_live) =~ "Edit Text"

      assert form_live
             |> form("#text-form", text: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert {:ok, index_live, _html} =
               form_live
               |> form("#text-form", text: @update_attrs)
               |> render_submit()
               |> follow_redirect(conn, ~p"/texts")

      html = render(index_live)
      assert html =~ "Text updated successfully"
      assert html =~ "some updated title"
    end

    test "deletes text in listing", %{conn: conn, text: text} do
      {:ok, index_live, _html} = live(conn, ~p"/texts")

      assert index_live |> element("#texts-#{text.id} a", "Delete") |> render_click()
      refute has_element?(index_live, "#texts-#{text.id}")
    end
  end

  describe "Show" do
    setup [:create_text]

    test "displays text", %{conn: conn, text: text} do
      {:ok, _show_live, html} = live(conn, ~p"/texts/#{text}")

      assert html =~ "Show Text"
      assert html =~ text.title
    end

    test "updates text and returns to show", %{conn: conn, text: text} do
      {:ok, show_live, _html} = live(conn, ~p"/texts/#{text}")

      assert {:ok, form_live, _} =
               show_live
               |> element("a", "Edit")
               |> render_click()
               |> follow_redirect(conn, ~p"/texts/#{text}/edit?return_to=show")

      assert render(form_live) =~ "Edit Text"

      assert form_live
             |> form("#text-form", text: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert {:ok, show_live, _html} =
               form_live
               |> form("#text-form", text: @update_attrs)
               |> render_submit()
               |> follow_redirect(conn, ~p"/texts/#{text}")

      html = render(show_live)
      assert html =~ "Text updated successfully"
      assert html =~ "some updated title"
    end
  end
end
