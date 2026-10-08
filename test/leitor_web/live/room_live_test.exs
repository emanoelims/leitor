defmodule LeitorWeb.RoomLiveTest do
  use LeitorWeb.ConnCase

  import Leitor.StudyFixtures
  import Phoenix.LiveViewTest

  @create_attrs %{position: 42, title: "some title", body: "some body", invite_code: "new invite_code"}
  @update_attrs %{
    position: 43,
    title: "some updated title",
    body: "some updated body",
    invite_code: "some updated invite_code"
  }
  @invalid_attrs %{position: nil, title: nil, body: nil, invite_code: nil}

  setup :register_and_log_in_user

  defp create_room(%{scope: scope}) do
    room = room_fixture(scope)

    %{room: room}
  end

  describe "Index" do
    setup [:create_room]

    test "lists all rooms", %{conn: conn, room: room} do
      {:ok, _index_live, html} = live(conn, ~p"/manage/rooms")

      assert html =~ "Listing Rooms"
      assert html =~ room.title
    end

    test "saves new room", %{conn: conn} do
      {:ok, index_live, _html} = live(conn, ~p"/manage/rooms")

      assert {:ok, form_live, _} =
               index_live
               |> element("a", "New Room")
               |> render_click()
               |> follow_redirect(conn, ~p"/manage/rooms/new")

      assert render(form_live) =~ "New Room"

      assert form_live
             |> form("#room-form", room: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert {:ok, index_live, _html} =
               form_live
               |> form("#room-form", room: @create_attrs)
               |> render_submit()
               |> follow_redirect(conn, ~p"/manage/rooms")

      html = render(index_live)
      assert html =~ "Room created successfully"
      assert html =~ "some title"
    end

    test "updates room in listing", %{conn: conn, room: room} do
      {:ok, index_live, _html} = live(conn, ~p"/manage/rooms")

      assert {:ok, form_live, _html} =
               index_live
               |> element("#rooms-#{room.id} a", "Edit")
               |> render_click()
               |> follow_redirect(conn, ~p"/manage/rooms/#{room}/edit")

      assert render(form_live) =~ "Edit Room"

      assert form_live
             |> form("#room-form", room: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert {:ok, index_live, _html} =
               form_live
               |> form("#room-form", room: @update_attrs)
               |> render_submit()
               |> follow_redirect(conn, ~p"/manage/rooms")

      html = render(index_live)
      assert html =~ "Room updated successfully"
      assert html =~ "some updated title"
    end

    test "deletes room in listing", %{conn: conn, room: room} do
      {:ok, index_live, _html} = live(conn, ~p"/manage/rooms")

      assert index_live |> element("#rooms-#{room.id} a", "Delete") |> render_click()
      refute has_element?(index_live, "#rooms-#{room.id}")
    end
  end

  describe "Show" do
    setup [:create_room]

    test "displays room", %{conn: conn, room: room} do
      {:ok, _show_live, html} = live(conn, ~p"/manage/rooms/#{room}")

      assert html =~ "Show Room"
      assert html =~ room.title
    end

    test "updates room and returns to show", %{conn: conn, room: room} do
      {:ok, show_live, _html} = live(conn, ~p"/manage/rooms/#{room}")

      assert {:ok, form_live, _} =
               show_live
               |> element("a", "Edit")
               |> render_click()
               |> follow_redirect(conn, ~p"/manage/rooms/#{room}/edit?return_to=show")

      assert render(form_live) =~ "Edit Room"

      assert form_live
             |> form("#room-form", room: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert {:ok, show_live, _html} =
               form_live
               |> form("#room-form", room: @update_attrs)
               |> render_submit()
               |> follow_redirect(conn, ~p"/manage/rooms/#{room}")

      html = render(show_live)
      assert html =~ "Room updated successfully"
      assert html =~ "some updated title"
    end
  end
end
