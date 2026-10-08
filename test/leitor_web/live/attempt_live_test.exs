defmodule LeitorWeb.AttemptLiveTest do
  use LeitorWeb.ConnCase

  import Leitor.LearningFixtures
  import Phoenix.LiveViewTest

  @create_attrs %{kind: "some kind", content: "some content", duration: 42}
  @update_attrs %{kind: "some updated kind", content: "some updated content", duration: 43}
  @invalid_attrs %{kind: nil, content: nil, duration: nil}

  setup :register_and_log_in_user

  defp create_attempt(%{scope: scope}) do
    attempt = attempt_fixture(scope)

    %{attempt: attempt}
  end

  describe "Index" do
    setup [:create_attempt]

    test "lists all attempts", %{conn: conn, attempt: attempt} do
      {:ok, _index_live, html} = live(conn, ~p"/attempts")

      assert html =~ "Listing Attempts"
      assert html =~ attempt.kind
    end

    test "saves new attempt", %{conn: conn} do
      {:ok, index_live, _html} = live(conn, ~p"/attempts")

      assert {:ok, form_live, _} =
               index_live
               |> element("a", "New Attempt")
               |> render_click()
               |> follow_redirect(conn, ~p"/attempts/new")

      assert render(form_live) =~ "New Attempt"

      assert form_live
             |> form("#attempt-form", attempt: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert {:ok, index_live, _html} =
               form_live
               |> form("#attempt-form", attempt: @create_attrs)
               |> render_submit()
               |> follow_redirect(conn, ~p"/attempts")

      html = render(index_live)
      assert html =~ "Attempt created successfully"
      assert html =~ "some kind"
    end

    test "updates attempt in listing", %{conn: conn, attempt: attempt} do
      {:ok, index_live, _html} = live(conn, ~p"/attempts")

      assert {:ok, form_live, _html} =
               index_live
               |> element("#attempts-#{attempt.id} a", "Edit")
               |> render_click()
               |> follow_redirect(conn, ~p"/attempts/#{attempt}/edit")

      assert render(form_live) =~ "Edit Attempt"

      assert form_live
             |> form("#attempt-form", attempt: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert {:ok, index_live, _html} =
               form_live
               |> form("#attempt-form", attempt: @update_attrs)
               |> render_submit()
               |> follow_redirect(conn, ~p"/attempts")

      html = render(index_live)
      assert html =~ "Attempt updated successfully"
      assert html =~ "some updated kind"
    end

    test "deletes attempt in listing", %{conn: conn, attempt: attempt} do
      {:ok, index_live, _html} = live(conn, ~p"/attempts")

      assert index_live |> element("#attempts-#{attempt.id} a", "Delete") |> render_click()
      refute has_element?(index_live, "#attempts-#{attempt.id}")
    end
  end

  describe "Show" do
    setup [:create_attempt]

    test "displays attempt", %{conn: conn, attempt: attempt} do
      {:ok, _show_live, html} = live(conn, ~p"/attempts/#{attempt}")

      assert html =~ "Show Attempt"
      assert html =~ attempt.kind
    end

    test "updates attempt and returns to show", %{conn: conn, attempt: attempt} do
      {:ok, show_live, _html} = live(conn, ~p"/attempts/#{attempt}")

      assert {:ok, form_live, _} =
               show_live
               |> element("a", "Edit")
               |> render_click()
               |> follow_redirect(conn, ~p"/attempts/#{attempt}/edit?return_to=show")

      assert render(form_live) =~ "Edit Attempt"

      assert form_live
             |> form("#attempt-form", attempt: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert {:ok, show_live, _html} =
               form_live
               |> form("#attempt-form", attempt: @update_attrs)
               |> render_submit()
               |> follow_redirect(conn, ~p"/attempts/#{attempt}")

      html = render(show_live)
      assert html =~ "Attempt updated successfully"
      assert html =~ "some updated kind"
    end
  end
end
