defmodule LeitorWeb.EntryLiveTest do
  use LeitorWeb.ConnCase

  import Leitor.LearningFixtures
  import Phoenix.LiveViewTest

  @create_attrs %{
    status: "some status",
    term: "new term",
    context: "some context",
    category: "some category",
    meaning: "some meaning",
    interval: 42,
    due_at: "2026-10-07T06:23:00Z"
  }
  @update_attrs %{
    status: "some updated status",
    term: "some updated term",
    context: "some updated context",
    category: "some updated category",
    meaning: "some updated meaning",
    interval: 43,
    due_at: "2026-10-08T06:23:00Z"
  }
  @invalid_attrs %{status: nil, term: nil, context: nil, category: nil, meaning: nil, interval: nil, due_at: nil}

  setup :register_and_log_in_user

  defp create_entry(%{scope: scope}) do
    entry = entry_fixture(scope)

    %{entry: entry}
  end

  describe "Index" do
    setup [:create_entry]

    test "lists all entries", %{conn: conn, entry: entry} do
      {:ok, _index_live, html} = live(conn, ~p"/entries")

      assert html =~ "Listing Entries"
      assert html =~ entry.term
    end

    test "saves new entry", %{conn: conn} do
      {:ok, index_live, _html} = live(conn, ~p"/entries")

      assert {:ok, form_live, _} =
               index_live
               |> element("a", "New Entry")
               |> render_click()
               |> follow_redirect(conn, ~p"/entries/new")

      assert render(form_live) =~ "New Entry"

      assert form_live
             |> form("#entry-form", entry: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert {:ok, index_live, _html} =
               form_live
               |> form("#entry-form", entry: @create_attrs)
               |> render_submit()
               |> follow_redirect(conn, ~p"/entries")

      html = render(index_live)
      assert html =~ "Entry created successfully"
      assert html =~ "some term"
    end

    test "updates entry in listing", %{conn: conn, entry: entry} do
      {:ok, index_live, _html} = live(conn, ~p"/entries")

      assert {:ok, form_live, _html} =
               index_live
               |> element("#entries-#{entry.id} a", "Edit")
               |> render_click()
               |> follow_redirect(conn, ~p"/entries/#{entry}/edit")

      assert render(form_live) =~ "Edit Entry"

      assert form_live
             |> form("#entry-form", entry: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert {:ok, index_live, _html} =
               form_live
               |> form("#entry-form", entry: @update_attrs)
               |> render_submit()
               |> follow_redirect(conn, ~p"/entries")

      html = render(index_live)
      assert html =~ "Entry updated successfully"
      assert html =~ "some updated term"
    end

    test "deletes entry in listing", %{conn: conn, entry: entry} do
      {:ok, index_live, _html} = live(conn, ~p"/entries")

      assert index_live |> element("#entries-#{entry.id} a", "Delete") |> render_click()
      refute has_element?(index_live, "#entries-#{entry.id}")
    end
  end

  describe "Show" do
    setup [:create_entry]

    test "displays entry", %{conn: conn, entry: entry} do
      {:ok, _show_live, html} = live(conn, ~p"/entries/#{entry}")

      assert html =~ "Show Entry"
      assert html =~ entry.term
    end

    test "updates entry and returns to show", %{conn: conn, entry: entry} do
      {:ok, show_live, _html} = live(conn, ~p"/entries/#{entry}")

      assert {:ok, form_live, _} =
               show_live
               |> element("a", "Edit")
               |> render_click()
               |> follow_redirect(conn, ~p"/entries/#{entry}/edit?return_to=show")

      assert render(form_live) =~ "Edit Entry"

      assert form_live
             |> form("#entry-form", entry: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert {:ok, show_live, _html} =
               form_live
               |> form("#entry-form", entry: @update_attrs)
               |> render_submit()
               |> follow_redirect(conn, ~p"/entries/#{entry}")

      html = render(show_live)
      assert html =~ "Entry updated successfully"
      assert html =~ "some updated term"
    end
  end
end
