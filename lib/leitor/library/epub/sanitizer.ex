defmodule Leitor.Library.Epub.Sanitizer do
  @moduledoc """
  Reduces EPUB XHTML to a small, inert HTML vocabulary.

  Only structural and inline text elements survive. Scripts, styles, forms, embedded objects, images, classes
  and event handlers are never kept. Whitespace is collapsed, so the stored markup is also the canonical text
  that annotations anchor to.

  Two modes share one implementation. With `import?: true` the sanitizer rewrites identifiers (`epub-` prefix) and
  resolves links through a `:links` map from archive paths to chapter ids. Without it, stored markup is only
  re-validated and left untouched, which makes sanitising stored content idempotent.
  """

  alias Leitor.Library.Epub.Package

  @typedoc "An HTML node as produced by `LazyHTML.to_tree/2`."
  @type html_node() :: String.t() | {String.t(), [{String.t(), String.t()}], [html_node()]}

  @max_bytes 4_000_000
  @max_depth 64
  @max_nodes 200_000
  @drop ~w(head script style svg math iframe object embed form noscript template title rt rp audio video canvas select textarea button)
  @keep ~w(p h1 h2 h3 h4 h5 h6 blockquote ul ol li dl dt dd pre code em strong i b u s sub sup small br hr table thead tbody tfoot tr th td figure figcaption a span section aside img)
  @void ~w(area base br col embed hr img input link meta source track wbr)
  @identifier ~r/^epub-[A-Za-z0-9_.:-]{1,200}$/
  @page_link ~r|^/pages/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}(#epub-[A-Za-z0-9_.:-]{1,200})?$|
  @fragment_link ~r/^#epub-[A-Za-z0-9_.:-]{1,200}$/
  @asset_path ~r|^/book-assets/([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})$|
  @default_asset_prefix "/book-assets/"
  @external_link ~r{^(https?://|mailto:)[^\s<>"'\x00-\x1f]+$}i

  @doc """
  Parses an XHTML or HTML document and returns the sanitised children of its body.

  ## Options

    * `:import?` - rewrite identifiers and links (default `false`).
    * `:links` - map from absolute archive paths to chapter ids, used with `:import?`.
    * `:path` - absolute archive path of the document, used to resolve relative links and images.
    * `:assets` - map from absolute archive paths to image ids, used with `:import?`. Images that are not
      listed are removed, so nothing remote or unknown is ever referenced.
    * `:asset_prefix` - path prefix written before image ids (default `"/book-assets/"`), so shared pages can
      serve images from a token-scoped route.
  """
  @spec tree(String.t(), keyword()) :: {:ok, [html_node()]} | {:error, :invalid_html}
  def tree(html, opts \\ [])

  def tree(html, opts) when is_binary(html) and byte_size(html) <= @max_bytes do
    context = %{
      import?: Keyword.get(opts, :import?, false),
      links: Keyword.get(opts, :links, %{}),
      assets: Keyword.get(opts, :assets, %{}),
      asset_prefix: Keyword.get(opts, :asset_prefix, @default_asset_prefix),
      directory: opts |> Keyword.get(:path, "/") |> Path.dirname(),
      pre?: false
    }

    cleaned = html |> parse() |> body() |> clean(context, 0)

    if count(cleaned) <= @max_nodes, do: {:ok, cleaned}, else: {:error, :invalid_html}
  end

  def tree(_html, _opts), do: {:error, :invalid_html}

  @doc "Parses XHTML or XML leniently into a tree, expanding the self-closing tags an HTML parser would otherwise nest."
  @spec parse(String.t()) :: [html_node() | {:comment, String.t()}]
  def parse(html), do: html |> expand_self_closing() |> LazyHTML.from_document() |> LazyHTML.to_tree()

  @doc "Serialises a sanitised tree."
  @spec to_html([html_node()]) :: String.t()
  def to_html(tree), do: tree |> LazyHTML.from_tree() |> LazyHTML.to_html()

  @doc "Returns the text of a tree, without markup."
  @spec text([html_node()] | html_node()) :: String.t()
  def text(nodes) when is_list(nodes), do: Enum.map_join(nodes, &text/1)
  def text(text) when is_binary(text), do: text
  def text({_tag, _attrs, children}), do: text(children)
  def text(_other), do: ""

  # XHTML allows `<a id="x"/>`; an HTML parser would treat that as an unclosed start tag and swallow what follows.
  defp expand_self_closing(html) do
    Regex.replace(~r|<([A-Za-z][\w:-]*)((?:\s[^<>]*?)?)\s*/>|, html, fn whole, tag, attrs ->
      if String.downcase(tag) in @void, do: whole, else: "<#{tag}#{attrs}></#{tag}>"
    end)
  end

  defp body(nodes) do
    case find(nodes, "body") do
      {"body", _attrs, children} -> children
      nil -> nodes
    end
  end

  defp find(nodes, tag) when is_list(nodes), do: Enum.find_value(nodes, &find(&1, tag))
  defp find({tag, _attrs, _children} = node, tag), do: node
  defp find({_other, _attrs, children}, tag), do: find(children, tag)
  defp find(_other, _tag), do: nil

  defp clean(nodes, context, depth), do: clean_list(nodes, context, depth, false)

  defp clean_list([], _context, _depth, _after_break?), do: []

  defp clean_list([{"br", _, _} = node | rest], context, depth, _after_break?),
    do: clean_node(node, context, depth) ++ clean_list(rest, context, depth, true)

  defp clean_list([text | rest], context, depth, after_break?) when is_binary(text),
    do: [text(text, context, after_break?) | clean_list(rest, context, depth, false)]

  defp clean_list([node | rest], context, depth, _after_break?),
    do: clean_node(node, context, depth) ++ clean_list(rest, context, depth, false)

  defp text(text, %{pre?: true}, _after_break?), do: text

  # Stored markup keeps the newline written after a break; imported markup gets its own from `line_break/1`.
  defp text("\n" <> text, %{import?: false}, true), do: "\n" <> collapse(text)
  defp text(text, %{import?: true}, true), do: text |> collapse() |> String.trim_leading(" ")
  defp text(text, _context, _after_break?), do: collapse(text)

  defp collapse(text), do: Regex.replace(~r/[ \t\n\r\f]+/, text, " ")

  defp clean_node({:comment, _}, _context, _depth), do: []

  defp clean_node({tag, attrs, children}, context, depth) do
    cond do
      tag in @drop -> []
      depth >= @max_depth -> [text(children)]
      tag == "br" -> line_break(context)
      tag in @keep -> keep(tag, attrs, children, context, depth)
      true -> clean(children, context, depth + 1)
    end
  end

  # The newline keeps words on either side of a break apart in the canonical text.
  defp line_break(%{import?: true}), do: [{"br", [], []}, "\n"]
  defp line_break(_context), do: [{"br", [], []}]

  defp keep(tag, attrs, children, context, depth) do
    attrs = attributes(tag, attrs, context)
    children = clean(children, %{context | pre?: context.pre? or tag == "pre"}, depth + 1)

    cond do
      tag == "img" -> if List.keymember?(attrs, "src", 0), do: [{tag, attrs, []}], else: []
      tag in ~w(span a) and not List.keymember?(attrs, "id", 0) and not List.keymember?(attrs, "href", 0) -> children
      true -> [{tag, attrs, children}]
    end
  end

  defp attributes(tag, attrs, context) do
    attrs
    |> Enum.flat_map(&attribute(tag, &1, context))
    |> Enum.uniq_by(&elem(&1, 0))
    |> external_link()
  end

  defp attribute(_tag, {"id", value}, %{import?: true}), do: [{"id", "epub-" <> identifier(value)}]
  defp attribute(_tag, {"id", value}, _context), do: if(Regex.match?(@identifier, value), do: [{"id", value}], else: [])

  defp attribute("img", {"src", value}, context) do
    case image(String.trim(value), context) do
      nil -> []
      src -> [{"src", src}]
    end
  end

  defp attribute("img", {"alt", value}, _context), do: [{"alt", String.slice(value, 0, 500)}]

  defp attribute("a", {"href", value}, context) do
    case link(String.trim(value), context) do
      nil -> []
      href -> [{"href", href}]
    end
  end

  defp attribute(tag, {name, value}, _context) when tag in ~w(td th) and name in ~w(colspan rowspan) do
    case Integer.parse(value) do
      {number, ""} when number in 1..100 -> [{name, value}]
      _ -> []
    end
  end

  defp attribute(_tag, _attribute, _context), do: []

  defp external_link(attrs) do
    case List.keyfind(attrs, "href", 0) do
      {_, "http" <> _} -> attrs ++ [{"rel", "noopener noreferrer"}, {"target", "_blank"}]
      _ -> attrs
    end
  end

  defp identifier(value), do: value |> String.replace(~r/[^A-Za-z0-9_.:-]/, "_") |> String.slice(0, 200)

  defp link("", _context), do: nil

  defp link(href, %{import?: true} = context) do
    cond do
      String.starts_with?(href, "#") ->
        if(href == "#", do: nil, else: "#epub-" <> identifier(String.trim_leading(href, "#")))

      Regex.match?(~r/^[A-Za-z][A-Za-z0-9+.-]*:/, href) ->
        validated_external(href)

      true ->
        chapter_link(href, context)
    end
  end

  defp link(href, _context) do
    if Regex.match?(@fragment_link, href) or Regex.match?(@page_link, href) or Regex.match?(@external_link, href),
      do: href
  end

  defp image(src, %{import?: true} = context) do
    with false <- src == "" or String.starts_with?(src, "//") or Regex.match?(~r/^[A-Za-z][A-Za-z0-9+.-]*:/, src),
         [file | _] <- String.split(src, "#"),
         path = file |> String.split("?") |> hd() |> Package.safe_decode() |> Path.expand(context.directory),
         {:ok, id} <- Map.fetch(context.assets, path) do
      context.asset_prefix <> id
    else
      _ -> nil
    end
  end

  defp image(src, context) do
    case Regex.run(@asset_path, src) do
      [_, id] -> context.asset_prefix <> id
      nil -> nil
    end
  end

  defp validated_external(href), do: if(Regex.match?(@external_link, href), do: href)

  defp chapter_link(href, context) do
    [file | fragment] = String.split(href, "#", parts: 2)
    path = file |> Package.safe_decode() |> Path.expand(context.directory)

    case context.links do
      %{^path => id} -> "/pages/#{id}" <> fragment_suffix(fragment)
      _ -> nil
    end
  end

  defp fragment_suffix([fragment]) when fragment != "", do: "#epub-" <> identifier(fragment)
  defp fragment_suffix(_other), do: ""

  defp count(nodes) when is_list(nodes), do: Enum.reduce(nodes, 0, &(count(&1) + &2))
  defp count({_tag, _attrs, children}), do: 1 + count(children)
  defp count(_text), do: 1
end
