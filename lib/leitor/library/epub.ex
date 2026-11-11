defmodule Leitor.Library.Epub do
  @moduledoc """
  Reads an EPUB as a book: metadata, a table of contents and one sanitised HTML chapter per spine document.

  Chapters get their identifiers up front so links between chapters can be rewritten to the pages they will
  become. Nothing is written to disk and every chapter is sanitised by `Leitor.Library.Epub.Sanitizer`.
  """

  alias Leitor.Library.Epub.Package
  alias Leitor.Library.Epub.Sanitizer

  @max_part 250_000
  @max_chapters 1_000
  @max_size 30_000_000
  @failure "We couldn't read this EPUB. Try exporting it again or paste its text."
  @empty "No readable text found in this EPUB."
  @too_large "A chapter of this EPUB is too large to import. Split it into smaller sections."

  @typedoc "A chapter ready to be stored as a text: its identifier, title, table-of-contents depth and sanitised HTML."
  @type chapter() :: %{id: Ecto.UUID.t(), title: String.t(), depth: non_neg_integer(), body: String.t()}
  @typedoc "An image the chapters reference, ready to be stored."
  @type asset() :: %{
          id: Ecto.UUID.t(),
          content_type: String.t(),
          byte_size: pos_integer(),
          digest: binary(),
          data: binary()
        }
  @typedoc "A book read from an EPUB archive."
  @type book() :: %{
          title: String.t(),
          author: String.t() | nil,
          language: String.t() | nil,
          identifier: String.t() | nil,
          chapters: [chapter()],
          assets: [asset()],
          cover_asset_id: Ecto.UUID.t() | nil,
          skipped_images: non_neg_integer()
        }

  @doc """
  Extracts a book from an EPUB file.

  Chapters follow the reading order. PNG, JPEG, GIF and WebP images referenced by the chapters, and the cover,
  are returned as assets; images that are too large, mislabelled, remote or unreferenced are left out and
  counted in `:skipped_images`. Titles come from the table of contents (EPUB 3 navigation document or
  EPUB 2 NCX), then the chapter's first heading, then a numbered fallback. A chapter larger than the text limit
  is split between top-level elements. Failures return a message that is safe to show.
  """
  @spec extract_book(Path.t()) :: {:ok, book()} | {:error, String.t()}
  def extract_book(path) do
    with {:ok, files} <- Package.read(path, @max_size),
         {:ok, package} <- Package.parse(files),
         {:ok, documents} <- Package.documents(files, package),
         true <- length(documents) <= @max_chapters,
         images = Package.images(path, package),
         ids = Map.new(images, fn {image_path, _image} -> {image_path, new_id()} end),
         {:ok, chapters} <- chapters(documents, toc(files, package), ids),
         [_ | _] <- chapters do
      {:ok, package |> book(chapters, images, ids) |> Map.put(:skipped_images, skipped_images(documents, chapters))}
    else
      [] -> {:error, @empty}
      {:error, message} when is_binary(message) -> {:error, message}
      _ -> {:error, @failure}
    end
  end

  defp book(%{xml: xml} = package, chapters, images, ids) do
    cover_id = ids[package.cover]

    %{
      title: metadata(xml, "title") || hd(chapters).title,
      author: metadata(xml, "creator"),
      language: metadata(xml, "language"),
      identifier: metadata(xml, "identifier"),
      chapters: chapters,
      assets: assets(chapters, cover_id, images, ids),
      cover_asset_id: cover_id
    }
  end

  # Images the documents mention that no chapter shows: too large, mislabelled, remote, or in a dropped document.
  defp skipped_images(documents, chapters) do
    mentioned = documents |> Enum.map(fn {_item, source} -> length(Regex.scan(~r/<img\b/i, source)) end) |> Enum.sum()
    shown = chapters |> Enum.map(fn chapter -> length(Regex.scan(~r/<img\b/, chapter.body)) end) |> Enum.sum()
    max(mentioned - shown, 0)
  end

  # Only images a chapter shows, and the cover, are stored.
  defp assets(chapters, cover_id, images, ids) do
    referenced =
      chapters
      |> Enum.flat_map(&Regex.scan(~r|src="/book-assets/([0-9a-f-]{36})"|, &1.body, capture: :all_but_first))
      |> List.flatten()
      |> MapSet.new()
      |> MapSet.put(cover_id)

    for_result =
      for {path, id} <- ids, id in referenced, %{content_type: type, data: data} = images[path] do
        %{id: id, content_type: type, byte_size: byte_size(data), digest: :crypto.hash(:sha256, data), data: data}
      end

    Enum.sort_by(for_result, & &1.id)
  end

  defp metadata(xml, name) do
    case Regex.run(Regex.compile!("<dc:#{name}\\b[^>]*>(.*?)</dc:#{name}>", "is"), xml) do
      [_, value] ->
        value
        |> String.replace(["<![CDATA[", "]]>"], "")
        |> LazyHTML.from_fragment()
        |> LazyHTML.text()
        |> normalize(180)

      nil ->
        nil
    end
  end

  defp normalize(text, limit) do
    normalized = text |> String.replace(~r/\s+/u, " ") |> String.trim() |> String.slice(0, limit)
    if normalized != "", do: normalized
  end

  # Documents without readable text are dropped before links are rewritten, so no link can point at a missing page.
  defp chapters(documents, toc, assets) do
    ids = Map.new(documents, fn {item, _source} -> {item.path, new_id()} end)

    with {:ok, sanitized} <- sanitize(documents, ids, assets),
         {:ok, readable} <- drop_unreadable(sanitized, documents, ids, assets) do
      readable |> Enum.with_index(1) |> split_all(ids, toc)
    end
  end

  defp drop_unreadable(sanitized, documents, ids, assets) do
    case for {item, nodes} <- sanitized, blank?(nodes), do: item.path do
      [] -> {:ok, sanitized}
      empty -> documents |> Enum.reject(&(elem(&1, 0).path in empty)) |> sanitize(Map.drop(ids, empty), assets)
    end
  end

  defp split_all([], _ids, _toc), do: {:ok, []}

  defp split_all([{{item, nodes}, index} | rest], ids, toc) do
    with {:ok, parts} <- split(nodes, item, index, ids, toc),
         {:ok, others} <- split_all(rest, ids, toc) do
      {:ok, parts ++ others}
    end
  end

  defp sanitize(documents, ids, assets) do
    documents
    |> Enum.reduce_while({:ok, []}, fn {item, source}, {:ok, acc} ->
      case Sanitizer.tree(source, import?: true, path: item.path, links: ids, assets: assets) do
        {:ok, nodes} -> {:cont, {:ok, [{item, unwrap(nodes)} | acc]}}
        {:error, _} -> {:halt, {:error, @failure}}
      end
    end)
    |> case do
      {:ok, acc} -> {:ok, Enum.reverse(acc)}
      error -> error
    end
  end

  # EPUB 3 chapters usually sit inside a single `<section>`; splitting needs the elements inside it.
  defp unwrap(nodes) do
    case Enum.reject(nodes, &(is_binary(&1) and String.trim(&1) == "")) do
      [{tag, _attrs, children}] when tag in ~w(section aside) -> unwrap(children)
      _ -> nodes
    end
  end

  defp blank?(nodes), do: nodes |> Sanitizer.text() |> String.trim() == ""

  defp split(nodes, item, index, ids, toc) do
    entry = Enum.find(toc, &(&1.path == item.path))
    title = (entry && entry.title) || heading(nodes) || "Chapter #{index}"
    depth = if entry, do: entry.depth, else: 0

    with {:ok, parts} <- parts(nodes) do
      total = length(parts)

      chapters =
        parts
        |> Enum.with_index(1)
        |> Enum.map(fn {part, number} ->
          %{
            id: if(number == 1, do: Map.fetch!(ids, item.path), else: new_id()),
            title: part_title(title, number, total),
            depth: depth,
            body: Sanitizer.to_html(part)
          }
        end)

      {:ok, chapters}
    end
  end

  defp part_title(title, _number, 1), do: String.slice(title, 0, 180)
  defp part_title(title, number, total), do: String.slice(title, 0, 160) <> " (#{number}/#{total})"

  defp parts(nodes) do
    nodes
    |> Enum.reduce_while({:ok, [], [], 0}, fn node, {:ok, done, current, size} ->
      bytes = byte_size(Sanitizer.to_html([node]))

      cond do
        bytes > @max_part -> {:halt, {:error, @too_large}}
        current != [] and size + bytes > @max_part -> {:cont, {:ok, [Enum.reverse(current) | done], [node], bytes}}
        true -> {:cont, {:ok, done, [node | current], size + bytes}}
      end
    end)
    |> case do
      {:ok, done, current, _size} ->
        {:ok, [Enum.reverse(current) | done] |> Enum.reverse() |> Enum.reject(&blank?/1)}

      error ->
        error
    end
  end

  defp heading(nodes) when is_list(nodes), do: Enum.find_value(nodes, &heading/1)
  defp heading({tag, _attrs, children}) when tag in ~w(h1 h2 h3), do: children |> Sanitizer.text() |> normalize(180)
  defp heading({_tag, _attrs, children}), do: heading(children)
  defp heading(_text), do: nil

  defp new_id, do: Ecto.UUID.generate(version: 7)

  # Table of contents: the EPUB 3 navigation document wins over the EPUB 2 NCX.
  defp toc(files, package) do
    items = Map.values(package.manifest)
    nav = Enum.find(items, &("nav" in &1.properties))
    ncx = package.manifest[package.toc] || Enum.find(items, &(&1.media_type == "application/x-dtbncx+xml"))

    cond do
      nav && files[nav.path] -> nav_entries(files[nav.path], nav.path)
      ncx && files[ncx.path] -> ncx_entries(files[ncx.path], ncx.path)
      true -> []
    end
  end

  defp nav_entries(source, path) do
    tree = Sanitizer.parse(source)
    nav = find_nav(tree)
    walk_nav(nav, -1, Path.dirname(path))
  end

  defp find_nav(tree) do
    navs = collect(tree, "nav")

    Enum.find(navs, fn {_tag, attrs, _children} ->
      Enum.any?(attrs, &(elem(&1, 0) in ~w(epub:type type) and elem(&1, 1) =~ "toc"))
    end) || List.first(navs)
  end

  defp collect(nodes, tag) when is_list(nodes), do: Enum.flat_map(nodes, &collect(&1, tag))
  defp collect({tag, _attrs, children} = node, tag), do: [node | collect(children, tag)]
  defp collect({_other, _attrs, children}, tag), do: collect(children, tag)
  defp collect(_text, _tag), do: []

  defp walk_nav(nil, _depth, _directory), do: []
  defp walk_nav(nodes, depth, directory) when is_list(nodes), do: Enum.flat_map(nodes, &walk_nav(&1, depth, directory))

  defp walk_nav({"a", attrs, children}, depth, directory) do
    entry(List.keyfind(attrs, "href", 0), Sanitizer.text(children), depth, directory)
  end

  defp walk_nav({"ol", _attrs, children}, depth, directory), do: walk_nav(children, depth + 1, directory)
  defp walk_nav({_tag, _attrs, children}, depth, directory), do: walk_nav(children, depth, directory)
  defp walk_nav(_text, _depth, _directory), do: []

  defp ncx_entries(source, path) do
    source |> Sanitizer.parse() |> collect("navmap") |> walk_ncx(-1, Path.dirname(path))
  end

  defp walk_ncx(nodes, depth, directory) when is_list(nodes), do: Enum.flat_map(nodes, &walk_ncx(&1, depth, directory))

  defp walk_ncx({"navpoint", _attrs, children}, depth, directory) do
    label = children |> collect("navlabel") |> Sanitizer.text()

    source =
      children
      |> collect("content")
      |> List.first()
      |> case do
        {_tag, attrs, _children} -> List.keyfind(attrs, "src", 0)
        nil -> nil
      end

    entry(source && {"href", elem(source, 1)}, label, depth + 1, directory) ++ walk_ncx(children, depth + 1, directory)
  end

  defp walk_ncx({_tag, _attrs, children}, depth, directory), do: walk_ncx(children, depth, directory)
  defp walk_ncx(_text, _depth, _directory), do: []

  defp entry({"href", href}, title, depth, directory) do
    with title when is_binary(title) <- normalize(title, 180),
         [file | _] <- String.split(href, "#"),
         true <- file != "" do
      [%{title: title, path: file |> Package.safe_decode() |> Path.expand(directory), depth: max(depth, 0)}]
    else
      _ -> []
    end
  end

  defp entry(_href, _title, _depth, _directory), do: []
end
