defmodule Leitor.PageDocument do
  @moduledoc "Safe Markdown pages with selectable prose blocks and UTF-8 byte anchors."

  @typedoc "Rendered page content and its canonical, selectable text."
  @type t() :: %{html: String.t(), blocks: [map()], text: String.t()}
  @typedoc "A validated selection in canonical page text."
  @type selection() :: %{
          from_offset: non_neg_integer(),
          to_offset: pos_integer(),
          quote: String.t(),
          block_index: non_neg_integer()
        }

  @syntax_highlight [engine: :lumis, opts: [formatter: :html_linked, budget: [time_limit: 1_000, match_limit: 4096]]]

  @doc "Renders Markdown with syntax-highlighted code, without executing HTML, HEEx, scripts, or remote images."
  @spec prepare(String.t()) :: t()
  def prepare(markdown) do
    document = MDEx.parse_document!(markdown, extension: [tasklist: true, strikethrough: true])
    {html, blocks} = render_nodes(document.nodes, [])
    %{html: html, blocks: blocks, text: Enum.map_join(blocks, "\n\n", & &1.text)}
  end

  @doc "Renders safe annotation Markdown. With a paragraph count, valid ¶ references become local source links; code and existing links are preserved."
  @spec render_answer(String.t()) :: String.t()
  @spec render_answer(String.t(), non_neg_integer()) :: String.t()
  def render_answer(markdown, paragraph_count \\ 0) do
    [document] = citation_nodes(MDEx.parse_document!(markdown), paragraph_count)

    MDEx.to_html!(document,
      syntax_highlight: @syntax_highlight,
      render: [unsafe: false, escape: true],
      sanitize: [rm_tags: ["img"]]
    )
  end

  defp citation_nodes(%MDEx.Text{literal: text}, count) do
    ~r/(\[¶\d{1,4}\]|¶\d{1,4})(?!\d)/u
    |> Regex.split(text, include_captures: true)
    |> Enum.map(&citation_part(&1, count))
  end

  defp citation_nodes(%{__struct__: module} = node, _count)
       when module in [MDEx.Link, MDEx.Image, MDEx.Code, MDEx.CodeBlock, MDEx.HtmlInline, MDEx.HtmlBlock], do: [node]

  defp citation_nodes(%{nodes: nodes} = node, count),
    do: [%{node | nodes: Enum.flat_map(nodes, &citation_nodes(&1, count))}]

  defp citation_nodes(node, _count), do: [node]

  defp citation_part(part, count) do
    case Regex.run(~r/^\[?¶(\d+)\]?$/u, part) do
      [_, number] ->
        index = String.to_integer(number) - 1

        if index >= 0 and index < count,
          do: %MDEx.Link{url: "#page-block-#{index}", nodes: [%MDEx.Text{literal: "¶#{number}"}]},
          else: %MDEx.Text{literal: part}

      nil ->
        %MDEx.Text{literal: part}
    end
  end

  @doc "Validates browser block offsets and derives the source quote; malformed or oversized selections return an error."
  @spec selection(t(), map()) :: {:ok, selection()} | {:error, :invalid_selection}
  def selection(document, %{"start_block" => first, "end_block" => last, "start_offset" => start, "end_offset" => finish})
      when is_integer(first) and is_integer(last) and is_integer(start) and is_integer(finish) and first >= 0 and
             last >= first and start >= 0 and finish >= 0 do
    with %{text: first_text} <- Enum.at(document.blocks, first),
         %{text: last_text} <- Enum.at(document.blocks, last),
         true <- start <= byte_size(first_text) and finish <= byte_size(last_text) do
      from = offset(document.blocks, first) + start
      to = offset(document.blocks, last) + finish
      selected(document.text, from, to, first)
    else
      _ -> {:error, :invalid_selection}
    end
  end

  def selection(_document, _attrs), do: {:error, :invalid_selection}

  @doc "Locates a saved quote after editing; ambiguous or removed quotes return nil rather than a wrong passage."
  @spec locate(t(), map()) :: selection() | nil
  def locate(document, mark) do
    case selected(document.text, mark.from_offset, mark.to_offset, mark.block_index) do
      {:ok, %{quote: quote} = selection} when quote == mark.quote -> selection
      _ -> locate_quote(document, mark.quote)
    end
  end

  defp locate_quote(document, quote) do
    case :binary.matches(document.text, quote) do
      [{from, size}] ->
        block = Enum.count(document.blocks, &(offset(document.blocks, &1.id) <= from)) - 1
        %{from_offset: from, to_offset: from + size, quote: quote, block_index: max(block, 0)}

      _ ->
        nil
    end
  end

  defp selected(text, from, to, block) when to > from and to <= byte_size(text) do
    quote = binary_part(text, from, to - from)

    if String.valid?(quote) and String.length(quote) <= 3000 and String.trim(quote) != "",
      do: {:ok, %{from_offset: from, to_offset: to, quote: quote, block_index: block}},
      else: {:error, :invalid_selection}
  end

  defp selected(_text, _from, _to, _block), do: {:error, :invalid_selection}

  defp offset(blocks, index), do: blocks |> Enum.take(index) |> Enum.reduce(0, &(byte_size(&1.text) + 2 + &2))

  defp render_nodes(nodes, blocks) do
    Enum.reduce(nodes, {"", blocks}, fn node, {html, blocks} ->
      {fragment, blocks} = render_node(node, blocks)
      {html <> fragment, blocks}
    end)
  end

  defp render_node(%MDEx.CodeBlock{info: info, literal: literal} = node, blocks) do
    if info in Leitor.Illustration.languages() do
      {Leitor.Illustration.render(literal, info), blocks}
    else
      render_prose_node(node, blocks)
    end
  end

  defp render_node(%{__struct__: module} = node, blocks) when module in [MDEx.Paragraph, MDEx.Heading, MDEx.CodeBlock] do
    render_prose_node(node, blocks)
  end

  defp render_node(%MDEx.List{nodes: nodes, list_type: type}, blocks) do
    tag = if type == :ordered, do: "ol", else: "ul"
    {html, blocks} = render_nodes(nodes, blocks)
    {"<#{tag}>#{html}</#{tag}>", blocks}
  end

  defp render_node(%MDEx.TaskItem{checked: checked, nodes: nodes}, blocks) do
    {html, blocks} = render_nodes(nodes, blocks)

    {~s(<li class="page-task"><input type="checkbox" disabled aria-label="Task completed" #{if checked, do: "checked", else: ""}>#{html}</li>),
     blocks}
  end

  defp render_node(%{__struct__: module, nodes: nodes}, blocks) when module in [MDEx.ListItem, MDEx.BlockQuote] do
    tag = if module == MDEx.BlockQuote, do: "blockquote", else: "li"
    {html, blocks} = render_nodes(nodes, blocks)
    {"<#{tag}>#{html}</#{tag}>", blocks}
  end

  defp render_node(node, blocks), do: {safe_html(node), blocks}

  defp render_prose_node(node, blocks) do
    id = length(blocks)
    text = prose(node)
    html = safe_html(node)

    if String.trim(text) == "" do
      {html, blocks}
    else
      {~s(<div class="page-prose-block"><span class="page-block-number" aria-hidden="true">#{id + 1}</span><div id="page-block-#{id}" data-page-block="#{id}">#{html}</div></div>),
       blocks ++ [%{id: id, text: text}]}
    end
  end

  # MDEx/Lumis trim trailing whitespace from highlighted code. Keep that suffix
  # outside the token spans so browser text and saved byte anchors stay identical.
  # A highlighting-budget fallback can retain its own newline; replace it too.
  defp safe_html(%MDEx.CodeBlock{literal: literal} = node) do
    code = String.trim_trailing(literal)
    ending = binary_part(literal, byte_size(code), byte_size(literal) - byte_size(code))

    node
    |> Map.put(:literal, code)
    |> render_html()
    |> String.replace(~r/\n*<\/code><\/pre>/, fn _ -> ending <> "</code></pre>" end)
  end

  defp safe_html(node), do: render_html(node)

  defp render_html(node) do
    MDEx.to_html!(%MDEx.Document{nodes: [node]},
      syntax_highlight: @syntax_highlight,
      render: [unsafe: false, escape: true],
      sanitize: [rm_tags: ["img"]]
    )
  end

  defp prose(%MDEx.Image{}), do: ""
  defp prose(%{literal: literal}), do: literal
  defp prose(%MDEx.SoftBreak{}), do: "\n"
  defp prose(%MDEx.LineBreak{}), do: "\n"
  defp prose(%{nodes: nodes}), do: Enum.map_join(nodes, &prose/1)
  defp prose(_node), do: ""
end
