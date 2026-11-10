defmodule Leitor.HtmlDocument do
  @moduledoc """
  Renders stored, sanitised chapter HTML as selectable prose blocks with UTF-8 byte anchors.

  The result has the same shape as `Leitor.PageDocument.prepare/1`, so selections, annotations, citations and
  sharing work unchanged. The text of every block is read back from the final block markup, which keeps the
  server-side bytes identical to the browser's `textContent` for the same element.

  Paragraphs, headings and preformatted text are blocks. List items, table cells, definitions and captions are
  blocks when they hold only inline content; otherwise they, and quotes, sections and figures, wrap the blocks
  they contain. Loose inline text inside a container becomes an anonymous paragraph.
  """

  alias Leitor.Library.Epub.Sanitizer

  @leaf ~w(p h1 h2 h3 h4 h5 h6 pre)
  @inline_leaf ~w(li dt dd td th figcaption)
  @structural ~w(ul ol dl table thead tbody tfoot tr)
  @container ~w(blockquote section aside figure)
  @block @leaf ++ @inline_leaf ++ @structural ++ @container ++ ["hr"]

  @typep state() :: %{blocks: [%{id: non_neg_integer(), text: String.t()}], count: non_neg_integer()}

  @doc """
  Sanitises stored chapter HTML again and renders it as selectable blocks.

  Markup that cannot be sanitised renders as an empty document.

  ## Examples

      iex> document = Leitor.HtmlDocument.prepare("<h1>Title</h1><p>One <em>two</em></p>")
      iex> Enum.map(document.blocks, & &1.text)
      ["Title", "One two"]
      iex> document.text
      "Title\\n\\nOne two"
  """
  @spec prepare(String.t()) :: Leitor.PageDocument.t()
  def prepare(html) when is_binary(html) do
    case Sanitizer.tree(html) do
      {:ok, tree} ->
        {parts, state} = render_children(tree, :flow, %{blocks: [], count: 0})
        blocks = Enum.reverse(state.blocks)
        %{html: IO.iodata_to_binary(parts), blocks: blocks, text: Enum.map_join(blocks, "\n\n", & &1.text)}

      {:error, :invalid_html} ->
        %{html: "", blocks: [], text: ""}
    end
  end

  @spec render_children([Sanitizer.html_node()], :flow | :structural, state()) :: {iodata(), state()}
  defp render_children(nodes, mode, state) do
    nodes
    |> Enum.chunk_by(&block?/1)
    |> Enum.reduce({[], state}, fn chunk, {acc, state} ->
      {html, state} = render_chunk(chunk, mode, state)
      {[acc, html], state}
    end)
  end

  defp render_chunk([first | _] = chunk, mode, state) do
    if block?(first) do
      Enum.reduce(chunk, {[], state}, fn node, {acc, state} ->
        {html, state} = render_block(node, state)
        {[acc, html], state}
      end)
    else
      inline_run(chunk, mode, state)
    end
  end

  # Loose text beside blocks is kept as a paragraph; inside lists and tables it is not valid content.
  defp inline_run(_nodes, :structural, state), do: {[], state}
  defp inline_run(nodes, :flow, state), do: leaf({"p", [], nodes}, state)

  defp render_block({"hr", _attrs, _children}, state), do: {"<hr>", state}
  defp render_block({tag, _attrs, _children} = node, state) when tag in @leaf, do: leaf(node, state)

  defp render_block({tag, _attrs, children} = node, state) when tag in @inline_leaf do
    if Enum.any?(children, &block?/1), do: container(node, :flow, state), else: inline_leaf(node, state)
  end

  defp render_block({tag, _attrs, _children} = node, state) when tag in @structural,
    do: container(node, :structural, state)

  defp render_block(node, state), do: container(node, :flow, state)

  defp container({tag, attrs, children}, mode, state) do
    {inner, state} = render_children(children, mode, state)
    {[open(tag, attrs), inner, close(tag)], state}
  end

  defp leaf({tag, attrs, children}, state) do
    children = if tag == "pre", do: children, else: trim(children)
    html = Sanitizer.to_html([{tag, attrs, children}])
    block(html, html, state)
  end

  defp inline_leaf({tag, attrs, children}, state) do
    inner = children |> trim() |> Sanitizer.to_html()
    {html, state} = block(inner, inner, state)

    # A cell without readable text stays in place so rows keep their shape.
    {[open(tag, attrs), if(html == [], do: inner, else: html), close(tag)], state}
  end

  defp block(html, source, state) do
    text = source |> LazyHTML.from_fragment() |> LazyHTML.text()

    if String.trim(text) == "" do
      {[], state}
    else
      id = state.count

      wrapped = [
        ~s(<div class="page-prose-block"><span class="page-block-number" aria-hidden="true">),
        Integer.to_string(id + 1),
        ~s(</span><div id="page-block-#{id}" data-page-block="#{id}">),
        html,
        "</div></div>"
      ]

      {wrapped, %{blocks: [%{id: id, text: text} | state.blocks], count: id + 1}}
    end
  end

  defp open(tag, attrs), do: ["<", tag, attrs |> Phoenix.HTML.attributes_escape() |> Phoenix.HTML.safe_to_string(), ">"]
  defp close(tag), do: ["</", tag, ">"]

  defp block?({tag, _attrs, _children}), do: tag in @block
  defp block?(_node), do: false

  defp trim(nodes), do: nodes |> trim(:left) |> trim(:right)

  defp trim(nodes, side), do: nodes |> flip(side) |> trim_first(side) |> flip(side)

  defp flip(nodes, :left), do: nodes
  defp flip(nodes, :right), do: Enum.reverse(nodes)

  defp trim_first([text | rest], side) when is_binary(text) do
    case trim_text(text, side) do
      "" -> trim_first(rest, side)
      trimmed -> [trimmed | rest]
    end
  end

  defp trim_first([{"br", _attrs, _children} | _rest] = nodes, _side), do: nodes

  defp trim_first([{tag, attrs, children} | rest], side) do
    case trim(children, side) do
      [] ->
        # An anchor target must survive even when it holds no text.
        if List.keymember?(attrs, "id", 0),
          do: [{tag, attrs, []} | trim_first(rest, side)],
          else: trim_first(rest, side)

      children ->
        [{tag, attrs, children} | rest]
    end
  end

  defp trim_first([], _side), do: []

  defp trim_text(text, :left), do: String.trim_leading(text, " ")
  defp trim_text(text, :right), do: String.trim_trailing(text, " ")
end
