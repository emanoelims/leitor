defmodule Leitor.IllustrationTest do
  use ExUnit.Case, async: true

  alias Leitor.Illustration
  alias Leitor.PageDocument
  alias Leitor.WritingDocument

  @svg ~s|<svg viewBox="0 0 800 400"><title>Lua &amp; mar</title><rect width="800" height="400" fill="#1d2939"/><circle cx="620" cy="100" r="45" fill="#f4dfaa"/></svg>|

  test "basic vectors render as inert images in editor previews and the reader, keeping prose anchors" do
    assert {:ok, "data:image/svg+xml;base64," <> data} = Illustration.image(@svg)
    assert Base.decode64!(data) =~ ~s|xmlns="http://www.w3.org/2000/svg"|
    assert Base.decode64!(data) =~ "Lua &amp; mar"
    markdown = "# Noite\n\n```leitor-svg-float\n#{@svg}\n```\n\n**Ana:** Olhe a lua.\n"
    assert Illustration.valid_markdown?(markdown)
    document = PageDocument.prepare(markdown)
    assert document.text == "Noite\n\nAna: Olhe a lua."
    assert length(document.blocks) == 2

    for html <- [document.html, WritingDocument.render(markdown)] do
      assert html =~ "data:image/svg+xml;base64,"
      assert html =~ ~s|width="800" height="400"|
      assert html =~ ~s|data-motion="float"|
      assert html =~ "data-illustration-toggle"
      refute html =~ "<svg"
      refute html =~ "LEITORILLUSTRATION"
    end
  end

  test "active SVG, external resources, malformed bounds and excessive content are refused" do
    bad = [
      ~s|<svg viewBox="0 0 10 10" onload="alert(1)"></svg>|,
      ~s|<svg viewBox="0 0 10 10"><script>alert(1)</script></svg>|,
      ~s|<svg viewBox="0 0 10 10"><foreignObject><p>HTML</p></foreignObject></svg>|,
      ~s|<svg viewBox="0 0 10 10"><image href="https://example.com/tracker"/></svg>|,
      ~s|<svg viewBox="0 0 10 10"><use href="#p"/></svg>|,
      ~s|<svg viewBox="0 0 10 10"><rect fill="url(https://example.com)"/></svg>|,
      ~s|<svg viewBox="0 0 10 10"><animate attributeName="opacity"/></svg>|,
      ~s|<!DOCTYPE svg><svg viewBox="0 0 10 10"></svg>|,
      ~s|<svg viewBox="bad"></svg>|,
      ~s|<svg viewBox="0 0 10 10"><g style="fill:red"/></svg>|,
      "<svg></svg><svg></svg>",
      String.duplicate("x", 65_537),
      nil,
      <<255>>,
      "<svg viewBox=\"0 0 10 10\">" <> String.duplicate("<g>", 30) <> String.duplicate("</g>", 30) <> "</svg>"
    ]

    for source <- bad do
      assert {:error, :invalid_svg} = Illustration.image(source)
    end

    unsafe = "```leitor-svg\n#{Enum.at(bad, 1)}\n```"
    refute Illustration.valid_markdown?(unsafe)
    assert WritingDocument.render(unsafe) =~ "Illustration unavailable"
    refute WritingDocument.render(unsafe) =~ "<script>"
    refute Illustration.valid_markdown?("```leitor-svg\n#{@svg}")
  end

  test "incomplete streaming illustrations use a loading state instead of an error" do
    preview = WritingDocument.render("```leitor-svg\n<svg")
    assert preview =~ "is-drawing"
    refute preview =~ "unavailable"
    refute Illustration.valid_markdown?("```leitor-svg\n<svg")
  end

  test "ordinary SVG examples stay code and raw HTML or remote images do not become illustrations" do
    markdown = "```svg\n#{@svg}\n```\n\n![remote](https://example.test/a.png)\n\n<script>alert(1)</script>"
    html = WritingDocument.render(markdown)
    refute html =~ "<img"
    refute html =~ "<script>"
    assert html =~ "<pre"
    assert Illustration.valid_markdown?(markdown)
  end
end
