defmodule Leitor.EpubFixtures do
  @moduledoc """
  Builds small EPUB archives in memory for import tests.

  Chapters are maps with a `:file` name, a `:title` for the table of contents and an HTML `:body`. The table of
  contents is an EPUB 3 navigation document (`:nav`), an EPUB 2 NCX (`:ncx`) or absent (`:none`).

  `:images` lists `%{file: "img/a.png", data: binary}` maps stored beside the chapters, and `:cover` is
  `{:property, file}` (EPUB 3) or `{:meta, file}` (EPUB 2) naming the cover among them.
  """

  @default_chapters [
    %{file: "one.xhtml", title: "The Beginning", body: "<h1>The Beginning</h1><p>First <em>chapter</em> text.</p>"},
    %{file: "two.xhtml", title: "The Middle", body: "<h1>The Middle</h1><p>Second chapter text.</p>"}
  ]

  @png Base.decode64!("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==")

  @doc "A valid one-pixel PNG."
  @spec png() :: binary()
  def png, do: @png

  @doc "Writes an EPUB to `path` and returns the path. Options: `:chapters`, `:toc`, `:title`, `:author`, `:language`."
  @spec write!(Path.t(), keyword()) :: Path.t()
  def write!(path, opts \\ []) do
    File.write!(path, binary!(opts))
    path
  end

  @doc "Returns the bytes of an EPUB archive; see `write!/2` for the options."
  @spec binary!(keyword()) :: binary()
  def binary!(opts \\ []) do
    chapters = Keyword.get(opts, :chapters, @default_chapters)
    toc = Keyword.get(opts, :toc, :nav)
    images = Keyword.get(opts, :images, [])

    entries =
      [
        {~c"mimetype", "application/epub+zip"},
        {~c"META-INF/container.xml", container()},
        {~c"OEBPS/content.opf", package(chapters, toc, opts)}
      ] ++
        toc_entries(chapters, toc) ++
        Enum.map(chapters, &{String.to_charlist("OEBPS/" <> &1.file), document(&1)}) ++
        Enum.map(images, &{String.to_charlist("OEBPS/" <> &1.file), &1.data})

    {:ok, {_name, data}} = :zip.create(~c"book.epub", entries, [:memory])
    data
  end

  defp container do
    """
    <?xml version="1.0"?>
    <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
      <rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles>
    </container>
    """
  end

  defp package(chapters, toc, opts) do
    items =
      Enum.map_join(chapters, "\n", fn chapter ->
        ~s(<item id="#{id(chapter)}" href="#{chapter.file}" media-type="application/xhtml+xml"/>)
      end)

    refs = Enum.map_join(chapters, "\n", &~s(<itemref idref="#{id(&1)}"/>))
    images = Keyword.get(opts, :images, [])
    cover = Keyword.get(opts, :cover)

    image_items =
      Enum.map_join(images, "\n", fn image ->
        properties = if cover == {:property, image.file}, do: ~s( properties="cover-image"), else: ""
        type = Map.get(image, :type, media_type(image.file))
        ~s(<item id="#{image_id(image)}" href="#{image.file}" media-type="#{type}"#{properties}/>)
      end)

    legacy_cover =
      case cover do
        {:meta, file} -> ~s(<meta name="cover" content="#{image_id(%{file: file})}"/>)
        _ -> ""
      end

    """
    <?xml version="1.0" encoding="UTF-8"?>
    <package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="uid">
      <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
        <dc:identifier id="uid">urn:uuid:12345</dc:identifier>
        <dc:title>#{Keyword.get(opts, :title, "A Small Book")}</dc:title>
        <dc:creator>#{Keyword.get(opts, :author, "Ada Writer")}</dc:creator>
        <dc:language>#{Keyword.get(opts, :language, "pt-BR")}</dc:language>
        #{legacy_cover}
      </metadata>
      <manifest>
        #{toc_manifest(toc)}
        #{items}
        #{image_items}
      </manifest>
      <spine#{if toc == :ncx, do: ~s( toc="ncx")}>
        #{refs}
      </spine>
    </package>
    """
  end

  defp toc_manifest(:nav), do: ~s(<item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>)
  defp toc_manifest(:ncx), do: ~s(<item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>)
  defp toc_manifest(:none), do: ""

  defp toc_entries(chapters, :nav) do
    links = Enum.map_join(chapters, "\n", &~s(<li><a href="#{&1.file}">#{&1.title}</a></li>))

    [
      {~c"OEBPS/nav.xhtml",
       """
       <?xml version="1.0" encoding="UTF-8"?>
       <html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
         <head><title>Contents</title></head>
         <body><nav epub:type="toc"><ol>#{links}</ol></nav></body>
       </html>
       """}
    ]
  end

  defp toc_entries(chapters, :ncx) do
    points =
      chapters
      |> Enum.with_index(1)
      |> Enum.map_join("\n", fn {chapter, index} ->
        """
        <navPoint id="p#{index}" playOrder="#{index}">
          <navLabel><text>#{chapter.title}</text></navLabel>
          <content src="#{chapter.file}"/>
        </navPoint>
        """
      end)

    [
      {~c"OEBPS/toc.ncx",
       """
       <?xml version="1.0" encoding="UTF-8"?>
       <ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1"><navMap>#{points}</navMap></ncx>
       """}
    ]
  end

  defp toc_entries(_chapters, :none), do: []

  defp document(chapter) do
    """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE html>
    <html xmlns="http://www.w3.org/1999/xhtml">
      <head><title>#{chapter.title}</title><style>p { color: red }</style></head>
      <body>#{chapter.body}</body>
    </html>
    """
  end

  defp id(chapter), do: "c-" <> Path.rootname(chapter.file)

  defp image_id(image), do: "i-" <> String.replace(image.file, ~r/[^A-Za-z0-9]/, "-")

  defp media_type(file) do
    case Path.extname(file) do
      ".png" -> "image/png"
      ".jpg" -> "image/jpeg"
      ".gif" -> "image/gif"
      ".webp" -> "image/webp"
      ".svg" -> "image/svg+xml"
    end
  end
end
