defmodule Leitor.SharingTest do
  use Leitor.DataCase, async: true

  import Leitor.AccountsFixtures

  alias Leitor.Accounts.Scope
  alias Leitor.Figures.Artifacts
  alias Leitor.Pages
  alias Leitor.Sharing
  alias Leitor.Sharing.Comment

  setup do
    scope = user_scope_fixture()

    {:ok, page} =
      Pages.create_page(scope, %{"title" => "A shared page", "body" => "A wonderful discovery.\n\nAnother sentence."})

    share = Sharing.ensure(scope, page.id)

    %{
      scope: scope,
      page: page,
      share: share,
      guest: Ecto.UUID.generate(),
      anchor: %{"start_block" => 0, "end_block" => 0, "start_offset" => 2, "end_offset" => 11}
    }
  end

  test "sharing starts restricted and management is strictly owner-scoped", %{scope: scope, page: page, share: share} do
    assert Sharing.ensure(scope, page.id).id == share.id
    assert {:error, :unavailable} = Sharing.resolve(nil, share.token)
    assert {:ok, %{role: "owner"}} = Sharing.resolve(scope, share.token)
    other = user_scope_fixture()
    assert_raise Ecto.NoResultsError, fn -> Sharing.ensure(other, page.id) end
    assert_raise Ecto.NoResultsError, fn -> Sharing.set_link(other, page.id, %{"link_role" => "view"}) end
    assert_raise Ecto.NoResultsError, fn -> Sharing.invite(other, page.id, %{}) end

    for token <- [nil, "", "invalid", String.duplicate("x", 43)] do
      assert {:error, :unavailable} = Sharing.resolve(nil, token)
    end

    assert {:error, changeset} = Sharing.set_link(scope, page.id, %{"link_role" => "edit"})
    refute changeset.valid?
    refute inspect(share) =~ share.token
  end

  test "email invitations require the matching confirmed account, and links can be revoked and rotated", %{
    scope: scope,
    page: page,
    share: share
  } do
    invited = user_scope_fixture()
    unconfirmed = Scope.for_user(unconfirmed_user_fixture())

    assert {:ok, member} =
             Sharing.invite(scope, page.id, %{
               "email" => String.upcase(invited.user.email),
               "role" => "comment",
               "share_id" => Ecto.UUID.generate()
             })

    assert member.share_id == share.id
    assert {:ok, %{role: "comment"}} = Sharing.resolve(invited, share.token)
    assert {:error, :unavailable} = Sharing.resolve(user_scope_fixture(), share.token)
    assert {:ok, _} = Sharing.invite(scope, page.id, %{"email" => unconfirmed.user.email, "role" => "view"})
    assert {:error, :unavailable} = Sharing.resolve(unconfirmed, share.token)
    assert {:ok, _} = Sharing.invite(scope, page.id, %{"email" => invited.user.email, "role" => "view"})
    assert {:ok, %{role: "view"}} = Sharing.resolve(invited, share.token)
    assert length(Sharing.collaborators(scope, page.id)) == 2
    assert {:ok, _} = Sharing.set_link(scope, page.id, %{"link_role" => "comment"})
    assert {:ok, %{role: "comment"}} = Sharing.resolve(nil, share.token)
    Sharing.remove_collaborator(scope, page.id, member.id)
    assert {:ok, %{role: "comment"}} = Sharing.resolve(invited, share.token)
    Sharing.remove_collaborator(scope, page.id, "invalid")
    assert {:ok, _} = Sharing.set_link(scope, page.id, %{"link_role" => "disabled"})
    assert {:error, :unavailable} = Sharing.resolve(invited, share.token)
    assert {:ok, _} = Sharing.invite(scope, page.id, %{"email" => invited.user.email, "role" => "comment"})
    rotated = Sharing.rotate(scope, page.id)
    refute rotated.token == share.token
    assert {:error, :unavailable} = Sharing.resolve(invited, share.token)
    assert {:ok, %{role: "comment"}} = Sharing.resolve(invited, rotated.token)
    assert Sharing.links_for(invited, [page.id]) == %{page.id => rotated.token}
    assert Sharing.links_for(user_scope_fixture(), [page.id]) == %{}
    assert {:error, %Ecto.Changeset{}} = Sharing.invite(scope, page.id, %{"email" => "bad", "role" => "owner"})
  end

  test "comments and replies validate source, attribution, permissions and current access", %{
    scope: scope,
    page: page,
    share: share,
    guest: guest,
    anchor: anchor
  } do
    {:ok, _} = Sharing.set_link(scope, page.id, %{"link_role" => "view"})

    attrs = %{
      "author_name" => " Guest ",
      "body" => " Is this right? ",
      "anchor" => anchor,
      "user_id" => scope.user.id,
      "quote" => "forged"
    }

    assert {:error, :forbidden} = Sharing.comment(nil, share.token, guest, attrs)
    {:ok, _} = Sharing.set_link(scope, page.id, %{"link_role" => "comment"})
    assert {:ok, comment} = Sharing.comment(nil, share.token, guest, attrs)
    assert comment.quote == "wonderful"
    assert comment.body == "Is this right?"
    assert comment.author_name == "Guest"
    assert is_nil(comment.user_id)
    assert Sharing.author?(nil, guest, comment)
    refute Sharing.author?(nil, Ecto.UUID.generate(), comment)
    refute Sharing.author?(scope, guest, comment)
    other = user_scope_fixture()

    assert {:ok, reply} =
             Sharing.comment(other, share.token, Ecto.UUID.generate(), %{
               "author_name" => "Other reader",
               "body" => "Yes",
               "parent_id" => comment.id
             })

    assert reply.parent_id == comment.id
    assert reply.user_id == other.user.id
    assert reply.quote == comment.quote
    assert {:ok, %{entries: [_, _], more?: false}} = Sharing.comments(nil, share.token)
    assert {:error, :forbidden} = Sharing.remove_comment(other, share.token, guest, comment.id)
    assert {:error, :forbidden} = Sharing.remove_comment(nil, share.token, Ecto.UUID.generate(), comment.id)
    assert {:ok, %{deleted_at: deleted}} = Sharing.remove_comment(scope, share.token, guest, comment.id)
    assert deleted
    assert Repo.get!(Comment, reply.id).body == "Yes"

    assert {:error, :invalid_selection} =
             Sharing.comment(nil, share.token, guest, %{
               "parent_id" => comment.id,
               "body" => "No",
               "author_name" => "Guest"
             })

    assert {:ok, _} = Sharing.remove_comment(other, share.token, guest, reply.id)
    assert {:error, :forbidden} = Sharing.remove_comment(nil, share.token, guest, "invalid")
    assert {:error, :invalid_selection} = Sharing.comment(nil, share.token, guest, Map.put(attrs, "anchor", %{}))
    assert {:error, %Ecto.Changeset{}} = Sharing.comment(nil, share.token, guest, Map.put(attrs, "body", ""))
    {:ok, _} = Sharing.set_link(scope, page.id, %{"link_role" => "disabled"})
    assert {:error, :unavailable} = Sharing.comment(nil, share.token, guest, attrs)
    assert {:error, :unavailable} = Sharing.comments(nil, share.token)
    assert {:error, :unavailable} = Sharing.remove_comment(nil, share.token, guest, reply.id)
  end

  test "guest deletion, source bounds, cross-page replies and comment rate limits", %{
    scope: scope,
    page: page,
    share: share,
    guest: guest,
    anchor: anchor
  } do
    {:ok, _} = Sharing.set_link(scope, page.id, %{"link_role" => "comment"})
    attrs = %{"author_name" => "Guest", "body" => "A thought", "anchor" => anchor}
    {:ok, comment} = Sharing.comment(nil, share.token, guest, attrs)
    assert {:ok, _} = Sharing.remove_comment(nil, share.token, guest, comment.id)
    {:ok, another} = Pages.create_page(scope, %{"title" => "Another", "body" => page.body})
    {:ok, another_share} = Sharing.set_link(scope, another.id, %{"link_role" => "comment"})
    {:ok, foreign} = Sharing.comment(nil, another_share.token, guest, attrs)

    assert {:error, :invalid_selection} =
             Sharing.comment(nil, share.token, guest, Map.put(attrs, "parent_id", foreign.id))

    assert {:error, :invalid_selection} = Sharing.comment(nil, share.token, guest, Map.put(attrs, "parent_id", "invalid"))
    assert {:error, :invalid_selection} = Sharing.comment(nil, share.token, guest, %{})
    for _ <- 1..5, do: assert({:ok, _} = Sharing.comment(nil, share.token, guest, attrs))
    assert {:error, :rate_limited} = Sharing.comment(nil, share.token, guest, attrs)
    assert {:ok, _} = Sharing.comment(nil, share.token, Ecto.UUID.generate(), attrs)
  end

  test "private annotations belong to the reader, appear in their notebook, and never leak to the source owner", %{
    scope: owner,
    page: page,
    share: share,
    anchor: anchor
  } do
    reader = user_scope_fixture()
    {:ok, _} = Sharing.set_link(owner, page.id, %{"link_role" => "view"})

    assert {:ok, mark} =
             Sharing.create_mark(reader, share.token, anchor, %{
               kind: "note",
               body: "My private thought",
               user_id: owner.user.id
             })

    assert mark.user_id == reader.user.id
    assert Pages.list_marks(owner, page.id) == []
    assert [%{id: id}] = Pages.list_marks(reader, page.id)
    assert id == mark.id
    assert Pages.notebook(reader).total == 1
    assert Pages.notebook(owner).total == 0
    assert_raise Ecto.NoResultsError, fn -> Pages.get_mark!(owner, mark.id) end
    assert {:error, :invalid_selection} = Sharing.create_mark(reader, share.token, %{}, %{kind: "highlight"})
    assert {:error, %Ecto.Changeset{}} = Sharing.create_mark(reader, share.token, anchor, %{kind: "bad"})
    {:ok, _} = Sharing.set_link(owner, page.id, %{"link_role" => "disabled"})
    assert {:error, :unavailable} = Sharing.create_mark(reader, share.token, anchor, %{kind: "highlight"})
    assert Pages.notebook(reader).total == 1
  end

  test "guest draft import is private, transactional and idempotent", %{
    scope: owner,
    page: page,
    share: share,
    anchor: anchor
  } do
    reader = user_scope_fixture()
    Sharing.set_link(owner, page.id, %{"link_role" => "view"})

    draft = %{
      "id" => "guest-" <> Ecto.UUID.generate(),
      "anchor" => anchor,
      "attrs" => %{"kind" => "note", "body" => "My draft", "user_id" => owner.user.id}
    }

    assert {:error, :invalid_selection} =
             Sharing.import_drafts(Scope.for_user(unconfirmed_user_fixture()), share.token, [draft])

    assert {:ok, 1} = Sharing.import_drafts(reader, share.token, [draft])
    assert {:ok, 1} = Sharing.import_drafts(reader, share.token, [draft])
    assert [%{user_id: id, body: "My draft"}] = Pages.list_marks(reader, page.id)
    assert id == reader.user.id
    assert Pages.list_marks(owner, page.id) == []
    fresh = Map.put(draft, "id", "guest-" <> Ecto.UUID.generate())
    assert {:error, :invalid_selection} = Sharing.import_drafts(reader, share.token, [fresh, %{}])
    assert length(Pages.list_marks(reader, page.id)) == 1
    assert {:error, :invalid_selection} = Sharing.import_drafts(reader, share.token, List.duplicate(draft, 101))
    Sharing.set_link(owner, page.id, %{"link_role" => "disabled"})
    assert {:error, :unavailable} = Sharing.import_drafts(reader, share.token, [fresh])
  end

  test "only embedded accepted figures of the source owner can be loaded", %{scope: scope, page: page, share: share} do
    attrs = %{
      title: "Lock",
      caption: "A mechanism",
      model: "test",
      source: %{"css" => ".test{}", "private" => "not shared"},
      report: %{"private" => true},
      status: "ready",
      bundle: "code",
      style: "css",
      preview: <<137, 80, 78, 71>>
    }

    {:ok, artifact} = Artifacts.store(scope, attrs)

    reference =
      Jason.encode!(%{
        engine: "anatomy-program",
        version: 1,
        artifact_id: artifact.id,
        title: "Lock",
        caption: "A mechanism"
      })

    {:ok, _} = Pages.update_page(scope, page, %{"body" => "# Public\n\n```leitor-figure\n#{reference}\n```"})
    {:ok, _} = Sharing.set_link(scope, page.id, %{"link_role" => "view"})
    assert {:ok, _} = Leitor.Figures.decode(reference)
    assert {:ok, payload} = Sharing.figure(nil, share.token, artifact.id)
    assert payload.bundle == "code"
    assert payload.custom_style == ".test{}"
    refute Map.has_key?(payload, :source)
    refute Map.has_key?(payload, :report)
    {:ok, unrelated} = Artifacts.store(scope, attrs)
    assert {:error, :unavailable} = Sharing.figure(nil, share.token, unrelated.id)
    assert {:error, :unavailable} = Sharing.figure(nil, share.token, "invalid")
    {:ok, foreign} = Artifacts.store(user_scope_fixture(), attrs)
    {:ok, draft} = Artifacts.store(scope, %{attrs | status: "draft"})

    for denied <- [foreign, draft] do
      reference =
        Jason.encode!(%{
          engine: "anatomy-program",
          version: 1,
          artifact_id: denied.id,
          title: "Lock",
          caption: "A mechanism"
        })

      Pages.update_page(scope, page, %{"body" => "```leitor-figure\n#{reference}\n```"})
      assert {:error, :unavailable} = Sharing.figure(nil, share.token, denied.id)
    end

    {:ok, _} = Sharing.set_link(scope, page.id, %{"link_role" => "disabled"})
    assert {:error, :unavailable} = Sharing.figure(nil, share.token, artifact.id)
  end

  test "subscriptions notify only invalidation, including edits", %{scope: scope, page: page, share: share} do
    {:ok, access} = Sharing.resolve(scope, share.token)
    assert :ok = Sharing.subscribe(access)
    {:ok, _} = Pages.update_page(scope, page, %{"body" => "Changed"})
    assert_receive :share_changed
    assert :ok = Sharing.page_changed(Ecto.UUID.generate())
  end
end
