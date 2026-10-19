defmodule LeitorWeb.SharedPageLiveTest do
  use LeitorWeb.ConnCase

  import Leitor.AccountsFixtures
  import Phoenix.LiveViewTest

  alias Leitor.Pages
  alias Leitor.Sharing

  setup do
    owner = user_scope_fixture()

    {:ok, page} =
      Pages.create_page(owner, %{
        "title" => "A shared discovery",
        "body" => "A wonderful discovery.\n\nA second paragraph."
      })

    {:ok, share} = Sharing.set_link(owner, page.id, %{"link_role" => "comment"})
    Application.put_env(:swoosh, :shared_test_process, self())
    on_exit(fn -> Application.delete_env(:swoosh, :shared_test_process) end)
    old = Application.get_env(:leitor, :language_adapter)
    Application.put_env(:leitor, :language_adapter, Leitor.LanguageStub)
    on_exit(fn -> Application.put_env(:leitor, :language_adapter, old) end)

    %{
      owner: owner,
      page: page,
      share: share,
      anchor: %{"start_block" => 0, "end_block" => 0, "start_offset" => 2, "end_offset" => 11}
    }
  end

  test "owner controls sharing while private page routes still require ownership", %{conn: conn, owner: owner, page: page} do
    {:ok, view, _} = live(log_in_user(conn, owner.user), ~p"/pages/#{page.id}")
    view |> element("#page-share") |> render_click()
    assert has_element?(view, "#page-sharing-dialog")
    view |> form("#page-link-access", share: %{link_role: "view"}) |> render_change()
    view |> form("#page-invite-form", invite: %{email: "invited@example.test", role: "comment"}) |> render_submit()
    assert [%{email: "invited@example.test"} = member] = Sharing.collaborators(owner, page.id)
    render_change(view, "collaborator-role", %{"id" => member.id, "collaborator" => %{"role" => "view"}})
    assert [%{role: "view"}] = Sharing.collaborators(owner, page.id)
    render_click(view, "renew-share-link")
    render_click(view, "remove-collaborator", %{"id" => member.id})
    assert Sharing.collaborators(owner, page.id) == []
    assert conn |> get(~p"/pages/#{page.id}") |> redirected_to() == ~p"/users/log-in"
  end

  test "visitors read and comment without accounts, guest notes stay separate, and revocation clears open readers", %{
    conn: conn,
    owner: owner,
    page: page,
    share: share,
    anchor: anchor
  } do
    {:ok, visitor, html} = live(conn, ~p"/s/#{share.token}")
    assert html =~ "A shared discovery"
    render_hook(visitor, "select", anchor)
    visitor |> element("#selection-comment") |> render_click()

    visitor
    |> form("#shared-comment-form", comment: %{author_name: "Visitor", body: "A shared question"})
    |> render_submit()

    assert has_element?(visitor, "#shared-comments", "A shared question")
    render_hook(visitor, "select", anchor)
    visitor |> element("#selection-highlight") |> render_click()
    assert has_element?(visitor, "#shared-personal-notes", "wonderful")
    assert Pages.list_marks(owner, page.id) == []
    render_hook(visitor, "select", anchor)
    visitor |> element("#selection-explain") |> render_click()
    assert has_element?(visitor, "#shared-action-error", "Sign in")
    {:ok, second, _} = live(conn, ~p"/s/#{share.token}")
    assert has_element?(second, "#shared-comments", "A shared question")
    refute has_element?(second, "#shared-personal-notes", "wonderful")
    Sharing.set_link(owner, page.id, %{"link_role" => "disabled"})
    assert render(visitor) =~ "This page is not available."
    refute has_element?(visitor, "#page-reading")
    refute render(visitor) =~ "A shared question"
  end

  test "view-only visitors cannot forge comments and login returns to the shared link", %{
    conn: conn,
    owner: owner,
    page: page,
    share: share,
    anchor: anchor
  } do
    {:ok, _} = Sharing.set_link(owner, page.id, %{"link_role" => "view"})
    {:ok, visitor, _} = live(conn, ~p"/s/#{share.token}")
    render_hook(visitor, "select", anchor)
    refute has_element?(visitor, "#selection-comment")
    render_click(visitor, "selection-mode", %{"mode" => "comment"})
    render_submit(visitor, "comment", %{"comment" => %{"author_name" => "Forged", "body" => "Cannot post"}})
    assert {:ok, %{entries: []}} = Sharing.comments(nil, share.token)
    login = get(conn, ~p"/s/#{share.token}/sign-in")
    assert redirected_to(login) == ~p"/users/log-in"
    assert get_session(login, :user_return_to) == ~p"/s/#{share.token}"
    private = get(conn, ~p"/s/#{share.token}")
    assert get_resp_header(private, "referrer-policy") == ["no-referrer"]
    assert get_resp_header(private, "x-robots-tag") == ["noindex, nofollow"]
  end

  test "reader AI and notes belong to the reader and use the reader allowance", %{
    conn: conn,
    owner: owner,
    page: page,
    share: share,
    anchor: anchor
  } do
    reader = user_scope_fixture()
    owner_before = Leitor.AI.usage(owner).used
    {:ok, view, _} = live(log_in_user(conn, reader.user), ~p"/s/#{share.token}")
    render_hook(view, "select", anchor)
    view |> element("#selection-explain") |> render_click()
    render_async(view)
    assert [%{id: mark_id, user_id: id, kind: "answer"}] = Pages.list_marks(reader, page.id)
    assert id == reader.user.id
    assert Pages.list_marks(owner, page.id) == []
    assert Leitor.AI.usage(owner).used == owner_before
    assert Leitor.AI.usage(reader).used > 0
    assert has_element?(view, "#shared-personal-notes")
    {:ok, owner_view, _} = live(log_in_user(conn, owner.user), ~p"/s/#{share.token}")
    refute render(owner_view) =~ "Very good or pleasing"
    {:ok, notebook, _} = live(log_in_user(conn, reader.user), ~p"/notebook")
    assert has_element?(notebook, "a[href^='/s/']")
    {:ok, returned, _} = live(log_in_user(conn, reader.user), ~p"/s/#{share.token}?#{[mark: mark_id]}")
    assert_push_event(returned, "page-jump", %{id: ^mark_id})
    assert has_element?(returned, "#personal-tab[aria-selected=true]")
  end

  test "source edits update open readers and discard an outdated selection", %{
    conn: conn,
    owner: owner,
    page: page,
    share: share,
    anchor: anchor
  } do
    {:ok, reader, _} = live(conn, ~p"/s/#{share.token}")
    render_hook(reader, "select", anchor)
    Pages.update_page(owner, page, %{"body" => "New source"})
    assert render(reader) =~ "New source"
    refute has_element?(reader, "#page-selection")
  end
end
