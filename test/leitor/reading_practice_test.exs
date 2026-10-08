defmodule Leitor.ReadingPracticeTest do
  use ExUnit.Case, async: true

  alias Leitor.Learning.Practice
  alias Leitor.Library.Import
  alias Leitor.Library.Reading

  test "sample and plain text preserve punctuation and bounded sentence size" do
    assert length(Reading.sample()) == 5
    assert [%{body: "Hello!"}, %{body: "How are you?"}] = Reading.prepare("Hello! How are you?")
    assert Enum.all?(Reading.prepare(String.duplicate("a", 6001)), &(String.length(&1.body) <= 3000))
    assert Reading.words("I'm HERE, café!") == ["i'm", "here", "café"]
  end

  test "dictation alignment handles omissions, additions, punctuation, and empty answers" do
    assert %{score: 100} = Practice.compare("Hello, world!", "HELLO WORLD")
    assert %{score: 50, correct: 1} = Practice.compare("Hello world", "Hello")
    assert %{score: 50} = Practice.compare("Hello", "Hello again")
    assert %{score: 0} = Practice.compare("Hello", "")
    assert %{score: 0} = Practice.compare("", "")
  end

  test "imports reject unsupported, invalid and empty documents and extract zipped XML" do
    path = Path.join(System.tmp_dir!(), "leitor-import-#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm(path) end)
    File.write!(path, "Hello world")
    assert {:ok, "Hello world"} = Import.extract(path, "notes.txt")
    assert {:error, _} = Import.extract(path, "notes.png")
    File.write!(path, <<255>>)
    assert {:error, _} = Import.extract(path, "notes.txt")
    File.write!(path, "   ")
    assert {:error, _} = Import.extract(path, "notes.txt")

    {:ok, {_, zip}} =
      :zip.create(~c"test.zip", [{~c"word/document.xml", "<w:p><w:t>Hello</w:t><w:t>world</w:t></w:p>"}], [:memory])

    File.write!(path, zip)
    assert {:ok, body} = Import.extract(path, "notes.docx")
    assert body =~ "Hello"
    assert body =~ "world"
    File.write!(path, "not a zip")
    assert {:error, _} = Import.extract(path, "broken.epub")
  end

  test "EPUB follows the package spine instead of ZIP order and skips navigation material" do
    path = Path.join(System.tmp_dir!(), "leitor-epub-#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm(path) end)
    container = ~s(<container><rootfiles><rootfile full-path="book/package.opf"/></rootfiles></container>)

    package =
      ~s(<package><manifest><item id="first" href="chapter1.xhtml"/><item id="second" href="chapter2.xhtml"/><item id="nav" href="nav.xhtml"/></manifest><spine><itemref idref="first"/><itemref idref="second"/></spine></package>)

    {:ok, {_, zip}} =
      :zip.create(
        ~c"book.epub",
        [
          {~c"book/chapter2.xhtml", "<p>Second chapter.</p>"},
          {~c"book/nav.xhtml", "<p>Contents navigation.</p>"},
          {~c"book/chapter1.xhtml", "<p>First chapter.</p>"},
          {~c"META-INF/container.xml", container},
          {~c"book/package.opf", package}
        ],
        [:memory]
      )

    File.write!(path, zip)
    assert {:ok, text} = Import.extract(path, "book.epub")
    assert text =~ ~r/First chapter.*Second chapter/s
    refute text =~ "Contents navigation"
  end

  @tag skip: is_nil(System.find_executable("tesseract"))
  test "local photo extraction works from a temporary directory" do
    path = Path.join(System.tmp_dir!(), "leitor-photo-#{System.unique_integer([:positive])}.png")
    File.cp!("test/fixtures/lesson.png", path)
    on_exit(fn -> File.rm(path) end)
    assert {:ok, "She went to school yesterday."} = Import.extract(path, "lesson.png")
  end
end
