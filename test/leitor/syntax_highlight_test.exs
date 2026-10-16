defmodule Leitor.SyntaxHighlightTest do
  use ExUnit.Case, async: true

  alias Leitor.PageDocument
  alias Leitor.WritingDocument

  test "pages, draft previews, and annotation answers highlight fenced code without changing its text" do
    code = "def hello(name), do: \"Olá, \#{name}\"\n"
    markdown = "```elixir\n#{code}```"
    document = PageDocument.prepare(markdown)

    assert document.text == code

    assert {:ok, %{quote: "Olá"}} =
             PageDocument.selection(document, %{
               "start_block" => 0,
               "end_block" => 0,
               "start_offset" => 22,
               "end_offset" => 26
             })

    for {html, expected} <- [
          {document.html, code},
          {WritingDocument.render(markdown), String.trim_trailing(code, "\n")},
          {PageDocument.render_answer(markdown), String.trim_trailing(code, "\n")}
        ] do
      fragment = LazyHTML.from_fragment(html)
      assert Enum.count(LazyHTML.query(fragment, "pre.lumis code.language-elixir")) == 1
      refute Enum.empty?(LazyHTML.query(fragment, "code span[class^=l-keyword]"))
      assert fragment |> LazyHTML.query("pre code") |> LazyHTML.text() == expected
      assert Enum.empty?(LazyHTML.query(fragment, "[style]"))
    end
  end

  test "installed grammars and common fence aliases produce colored tokens" do
    for {language, code} <- [
          {"js", "const answer = 42;"},
          {"ts", "const answer: number = 42;"},
          {"tsx", "const view = <p>Hello</p>;"},
          {"html", "<p class=\"hello\">Hello</p>"},
          {"css", "body { color: red; }"},
          {"json", "{\"answer\": 42}"},
          {"python", "def hello():\n    return True"},
          {"bash", "echo \"Hello\""},
          {"heex", "<div :if={@visible}>Hello</div>"}
        ] do
      html = PageDocument.render_answer("```#{language}\n#{code}\n```")
      assert html =~ "class=\"lumis\"", language
      assert html =~ "class=\"l-", language

      assert html
             |> LazyHTML.from_fragment()
             |> LazyHTML.query("pre code")
             |> LazyHTML.text()
             |> String.trim_trailing("\n") == String.trim_trailing(code, "\n")
    end
  end

  test "code line endings preserve browser text offsets across following paragraphs" do
    for language <- ["elixir", "unknown"], ending <- ["\n", "\n\n", "\n\n\n", "  \n", "\t\n\n"] do
      source = "First.\n\n```#{language}\n# Olá\nvalue = 42#{ending}```\n\nAfter the code."
      document = PageDocument.prepare(source)
      fragment = LazyHTML.from_fragment(document.html)
      browser_blocks = fragment |> LazyHTML.query("[data-page-block]") |> Enum.map(&LazyHTML.text/1)

      assert browser_blocks == Enum.map(document.blocks, & &1.text)
      assert Enum.join(browser_blocks, "\n\n") == document.text

      assert PageDocument.selection(document, %{
               "start_block" => 1,
               "end_block" => 2,
               "start_offset" => 0,
               "end_offset" => 5
             }) ==
               {:ok,
                %{
                  from_offset: 8,
                  to_offset: byte_size(document.text) - byte_size(" the code."),
                  quote: "# Olá\nvalue = 42#{ending}\n\nAfter",
                  block_index: 1
                }}
    end
  end

  test "uninstalled and omitted languages fall back to escaped plain code" do
    code = "<script>alert('example')</script>\n"

    for language <- ["", "not-an-installed-language"] do
      markdown = "```#{language}\n#{code}```"

      for html <- [
            PageDocument.prepare(markdown).html,
            WritingDocument.render(markdown),
            PageDocument.render_answer(markdown)
          ] do
        fragment = LazyHTML.from_fragment(html)

        assert fragment |> LazyHTML.query("pre code") |> LazyHTML.text() |> String.trim_trailing("\n") ==
                 String.trim_trailing(code, "\n")

        assert Enum.empty?(LazyHTML.query(fragment, "script"))
        assert Enum.empty?(LazyHTML.query(fragment, "code span[class^=l-]:not(.l-line)"))
      end
    end
  end

  test "highlighting preserves sanitization and leaves inline code and citations literal" do
    markdown = """
    ```html
    <img src=x onerror=alert(1)><script>alert(1)</script>
    ```

    <script>alert(2)</script>

    ![remote](https://example.com/tracker.png)

    [bad](javascript:alert(3))

    `¶1` and ¶1.
    """

    for html <- [
          PageDocument.prepare(markdown).html,
          WritingDocument.render(markdown),
          PageDocument.render_answer(markdown, 1)
        ] do
      fragment = LazyHTML.from_fragment(html)
      assert Enum.empty?(LazyHTML.query(fragment, "img, script, [onerror], a[href^='javascript:']"))

      assert fragment |> LazyHTML.query("pre code") |> LazyHTML.text() |> String.trim_trailing("\n") ==
               "<img src=x onerror=alert(1)><script>alert(1)</script>"

      assert html =~ "<code>¶1</code>"
    end

    assert PageDocument.render_answer(markdown, 1) =~ ~s(href="#page-block-0")
  end
end
