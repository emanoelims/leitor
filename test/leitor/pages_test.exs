defmodule Leitor.PagesTest do
  use Leitor.DataCase

  import Leitor.AccountsFixtures

  alias Leitor.PageDocument
  alias Leitor.Pages
  alias Leitor.Pages.Reply

  test "the global notebook filters owned annotations and only preloads source titles" do
    scope = user_scope_fixture()
    other = user_scope_fixture()
    {:ok, first} = Pages.create_page(scope, %{"title" => "Field_100%", "body" => "An apple thought."})
    {:ok, second} = Pages.create_page(scope, %{"title" => "FieldA1000", "body" => "An apple thought."})
    {:ok, secret} = Pages.create_page(other, %{"title" => "Private source", "body" => "An apple thought."})
    anchor = %{"start_block" => 0, "end_block" => 0, "start_offset" => 3, "end_offset" => 8}
    {:ok, note} = Pages.create_mark(scope, first.id, anchor, %{kind: "note", body: "A careful observation."})
    {:ok, definition} = Pages.create_mark(scope, second.id, anchor, %{kind: "definition", body: "A fruit."})
    {:ok, _} = Pages.create_mark(other, secret.id, anchor, %{kind: "note", body: "A private observation."})
    assert %{total: 2, entries: entries} = Pages.notebook(scope)
    assert MapSet.new(Enum.map(entries, & &1.id)) == MapSet.new([note.id, definition.id])
    assert Enum.all?(entries, &(&1.text.id == &1.text_id && &1.text.body == nil))
    assert %{total: 1, entries: [%{id: id}]} = Pages.notebook(scope, %{kind: "note", search: "CAREFUL"})
    assert id == note.id
    assert %{total: 1, entries: [%{id: ^id}]} = Pages.notebook(scope, %{search: "Field_100%"})
    assert %{total: 1} = Pages.notebook(scope, %{text_id: first.id})
    assert %{total: 0, entries: []} = Pages.notebook(scope, %{text_id: secret.id})
    assert %{total: 0} = Pages.notebook(scope, %{search: "private"})
    assert %{total: 0} = Pages.notebook(scope, %{kind: "highlight"})
    assert Pages.notebook_sources(scope) == [%{id: second.id, title: second.title}, %{id: first.id, title: first.title}]
  end

  test "the global notebook paginates without dropping entries and clamps empty pages" do
    scope = user_scope_fixture()
    {:ok, page} = Pages.create_page(scope, %{"title" => "Notes", "body" => "An apple thought."})
    anchor = %{"start_block" => 0, "end_block" => 0, "start_offset" => 3, "end_offset" => 8}

    ids =
      for n <- 1..31 do
        {:ok, note} = Pages.create_mark(scope, page.id, anchor, %{kind: "note", body: "Thought #{n}"})
        note.id
      end

    assert %{entries: first, total: 31, page: 1, per_page: 30} = Pages.notebook(scope)
    assert length(first) == 30
    assert %{entries: [last], page: 2} = Pages.notebook(scope, %{}, 100)
    assert MapSet.new(Enum.map(first, & &1.id) ++ [last.id]) == MapSet.new(ids)
    assert %{entries: [], total: 0, page: 1} = Pages.notebook(scope, %{search: "missing"}, 100)
  end

  test "Markdown remains formatted and canonical anchors exclude HTML and image execution" do
    document =
      PageDocument.prepare(
        "# A heading\n\nA **bold** word and *italic* thought.\n\n- A list item\n\n> A quote\n\n<script>alert('x')</script>\n\n![remote](https://example.test/x.png)"
      )

    assert document.html =~ "<h1>A heading</h1>"
    assert document.html =~ "<strong>bold</strong>"
    assert document.html =~ "<ul>"
    assert document.html =~ "<blockquote>"
    refute document.html =~ "<script>"
    refute document.html =~ "<img"
    assert Enum.at(document.blocks, 1).text == "A bold word and italic thought."

    assert {:ok, %{quote: "bold word"}} =
             PageDocument.selection(document, %{
               "start_block" => 1,
               "end_block" => 1,
               "start_offset" => 2,
               "end_offset" => 11
             })
  end

  test "checklists render their state without changing selectable text" do
    document = PageDocument.prepare("- [x] Completed\n- [ ] Pending")
    assert document.html =~ ~s(aria-label="Task completed" checked)
    assert Enum.map(document.blocks, & &1.text) == ["Completed", "Pending"]
  end

  test "UTF-8 anchors validate both endpoints and span formatted blocks" do
    document = PageDocument.prepare("Café and tea.\n\nAnother paragraph.")

    assert {:ok, %{quote: "Café"}} =
             PageDocument.selection(document, %{
               "start_block" => 0,
               "end_block" => 0,
               "start_offset" => 0,
               "end_offset" => 5
             })

    assert {:error, :invalid_selection} =
             PageDocument.selection(document, %{
               "start_block" => 0,
               "end_block" => 0,
               "start_offset" => 0,
               "end_offset" => 4
             })

    assert {:ok, %{quote: "tea.\n\nAnother"}} =
             PageDocument.selection(document, %{
               "start_block" => 0,
               "end_block" => 1,
               "start_offset" => 10,
               "end_offset" => 7
             })

    for anchor <- [
          %{},
          %{"start_block" => -1, "end_block" => 0, "start_offset" => 0, "end_offset" => 1},
          %{"start_block" => 99, "end_block" => 99, "start_offset" => 0, "end_offset" => 1},
          %{"start_block" => 0, "end_block" => 0, "start_offset" => 6, "end_offset" => 2}
        ] do
      assert {:error, :invalid_selection} = PageDocument.selection(document, anchor)
    end
  end

  test "pages may start blank, and annotations are owned and quoted from persisted text" do
    scope = user_scope_fixture()
    stranger = user_scope_fixture()
    assert {:ok, page} = Pages.create_page(scope)
    assert page.body == ""
    assert {:ok, page} = Pages.update_page(scope, page, %{"title" => "My page", "body" => "A wonderful sentence."})
    anchor = %{"start_block" => 0, "end_block" => 0, "start_offset" => 2, "end_offset" => 11}

    assert {:ok, mark} =
             Pages.create_mark(scope, page.id, anchor, %{kind: "highlight", quote: "forged", text_id: "forged"})

    assert mark.quote == "wonderful"
    assert Pages.list_marks(stranger, page.id) == []
    assert_raise Ecto.NoResultsError, fn -> Pages.get_page!(stranger, page.id) end
    assert_raise Ecto.NoResultsError, fn -> Pages.get_mark!(stranger, mark.id) end
    assert_raise Ecto.NoResultsError, fn -> Pages.update_mark(stranger, mark.id, %{color: "blue"}) end
    assert_raise Ecto.NoResultsError, fn -> Pages.delete_mark(stranger, mark.id) end
    assert {:ok, _} = Pages.update_mark(scope, mark.id, %{color: "green"})
    assert {:error, _} = Pages.create_mark(scope, page.id, anchor, %{kind: "note", body: ""})
    assert {:error, _} = Pages.create_mark(scope, page.id, %{}, %{kind: "highlight"})
    assert {:ok, _} = Pages.delete_mark(scope, mark.id)
    assert Pages.list_marks(scope, page.id) == []
  end

  test "editing reanchors unique quotes and refuses removed or ambiguous ones" do
    document = PageDocument.prepare("A meaningful thought.")

    {:ok, selection} =
      PageDocument.selection(document, %{"start_block" => 0, "end_block" => 0, "start_offset" => 2, "end_offset" => 12})

    changed = PageDocument.prepare("A new opening.\n\nA meaningful thought.")
    assert %{block_index: 1, quote: "meaningful"} = PageDocument.locate(changed, selection)
    assert PageDocument.locate(PageDocument.prepare("A different thought."), selection) == nil
    assert PageDocument.locate(PageDocument.prepare("First meaningful.\n\nThen meaningful."), selection) == nil
  end

  test "follow-ups validate their shape, remain owned, and survive a page reopen" do
    scope = user_scope_fixture()
    stranger = user_scope_fixture()
    {:ok, page} = Pages.create_page(scope, %{"title" => "A passage", "body" => "A wonderful sentence."})
    anchor = %{"start_block" => 0, "end_block" => 0, "start_offset" => 2, "end_offset" => 11}
    {:ok, mark} = Pages.create_mark(scope, page.id, anchor, %{kind: "definition", body: "Very good."})

    assert {:ok, %Reply{question: "em português", body: "Muito bom."}} =
             Reply.new(%{question: "em português", body: "Muito bom."})

    assert {:error, _} = Reply.new(%{question: " ", body: "A reply."})
    assert {:error, _} = Reply.new(%{question: String.duplicate("x", 501), body: "A reply."})
    assert {:error, _} = Reply.new(%{question: "Why?", body: ""})
    assert_raise Ecto.NoResultsError, fn -> Pages.append_reply(stranger, mark.id, %{question: "Why?", body: "No."}) end
    assert {:ok, updated} = Pages.append_reply(scope, mark.id, %{question: "em português", body: "Muito bom."})
    assert [%Reply{id: id, body: "Muito bom."}] = updated.replies
    assert is_binary(id)
    assert [%Reply{question: "em português"}] = Pages.get_mark!(scope, mark.id).replies
    assert Pages.get_mark!(scope, mark.id).body == "Very good."
    assert {:error, _} = Pages.append_reply(scope, mark.id, %{question: "Why?", body: ""})

    for n <- 2..20,
        do: assert({:ok, _} = Pages.append_reply(scope, mark.id, %{question: "Question #{n}", body: "Answer #{n}"}))

    assert {:error, _} = Pages.append_reply(scope, mark.id, %{question: "One too many", body: "A reply."})
    assert length(Pages.get_mark!(scope, mark.id).replies) == 20
  end

  test "annotation Markdown keeps emphasis without executing HTML, images, or JavaScript links" do
    html =
      PageDocument.render_answer(
        "**The main idea.**\n\n<script>alert('x')</script>\n\n![image](https://example.test/x.png)\n\n[bad](javascript:alert(1))"
      )

    assert html =~ "<strong>The main idea.</strong>"
    refute html =~ "<script>"
    refute html =~ "<img"
    refute html =~ "href=\"javascript:"
  end

  test "paragraph citations link only existing source blocks and preserve code and existing links" do
    html = PageDocument.render_answer("**See [¶2].** Also ¶1, [¶0] and [¶9]. `¶1` [¶1](https://example.test)", 2)
    parsed = LazyHTML.from_fragment(html)
    assert parsed |> LazyHTML.query(~s(strong a[href="#page-block-1"])) |> LazyHTML.text() == "¶2"
    assert parsed |> LazyHTML.query(~s(a[href="#page-block-0"])) |> LazyHTML.text() == "¶1"
    assert html =~ "[¶0]"
    assert html =~ "[¶9]"
    assert html =~ "<code>¶1</code>"
    assert parsed |> LazyHTML.query(~s(a[href="https://example.test"])) |> LazyHTML.text() == "¶1"
    refute PageDocument.render_answer("[¶1]") =~ "#page-block"
  end
end
