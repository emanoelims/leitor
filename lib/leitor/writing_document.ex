defmodule Leitor.WritingDocument do
  @moduledoc """
  Markdown drafts, safe presentation, and source ranges for paragraph feedback.

  Legacy drafts use the `plain` format: every nonempty line is a paragraph.
  Markdown drafts use CommonMark blocks; headings and list items are reviewable,
  while fenced code and dividers are excluded. Source ranges are UTF-8 byte offsets.
  User content is never compiled as HEEx or evaluated as a Phoenix component.
  """

  @typedoc "The persisted representation of a draft."
  @type format :: String.t()
  @typedoc "An editable prose block and its byte range in the original draft."
  @type paragraph :: %{start: non_neg_integer(), length: non_neg_integer(), text: String.t()}

  @syntax_highlight [engine: :lumis, opts: [formatter: :html_linked, budget: [time_limit: 1_000, match_limit: 4096]]]

  @doc "Normalizes a persisted or submitted format, defaulting legacy drafts to plain text."
  @spec format(map()) :: format()
  def format(%{"format" => "markdown"}), do: "markdown"
  def format(_attrs), do: "plain"

  @doc "Returns prose blocks in document order without changing their source text."
  @spec paragraphs(String.t(), format()) :: [paragraph()]
  def paragraphs(text, "plain") do
    ~r/[^\n]+/u
    |> Regex.scan(text, return: :index)
    |> Enum.map(fn [{start, length}] -> fragment(text, start, length) end)
    |> Enum.reject(&(String.trim(&1.text) == ""))
  end

  def paragraphs(text, "markdown") do
    {offsets, _size} = Enum.map_reduce(String.split(text, "\n"), 0, &{&2, &2 + byte_size(&1) + 1})

    text
    |> MDEx.parse_document!(extension: [tasklist: true, strikethrough: true])
    |> blocks()
    |> Enum.reject(&(String.trim(prose(&1)) == ""))
    |> Enum.map(fn %{sourcepos: %{start: {line, column}, end: {last_line, last_column}}} ->
      start = Enum.at(offsets, line - 1) + column - 1
      finish = Enum.at(offsets, last_line - 1) + last_column
      fragment(text, start, finish - start)
    end)
  end

  @doc "Finds a reviewable paragraph; negative and out-of-range selections return nil."
  @spec paragraph(String.t(), format(), integer()) :: paragraph() | nil
  def paragraph(text, format, index) when index >= 0, do: Enum.at(paragraphs(text, format), index)
  def paragraph(_text, _format, _index), do: nil

  @doc "Counts prose words, excluding Markdown markers and fenced code."
  @spec word_count(String.t(), format()) :: non_neg_integer()
  def word_count(text, "plain"), do: length(String.split(text))

  def word_count(text, "markdown") do
    text
    |> MDEx.parse_document!(extension: [tasklist: true, strikethrough: true])
    |> prose()
    |> String.split()
    |> length()
  end

  @doc "Renders sanitized Markdown with syntax-highlighted code; raw HTML and remote images remain disabled."
  @spec render(String.t()) :: String.t()
  def render(text) do
    document = MDEx.parse_document!(text, extension: [tasklist: true, strikethrough: true])
    {document, illustrations} = extract_illustrations(document, [])

    html =
      MDEx.to_html!(document,
        extension: [tasklist: true, strikethrough: true],
        syntax_highlight: @syntax_highlight,
        render: [unsafe: false, escape: true, tasklist_classes: true],
        sanitize: [
          rm_tags: ["img"],
          add_tags: ["input"],
          add_tag_attributes: %{
            "input" => ["type", "checked", "disabled", "aria-label"],
            "ul" => ["class"],
            "li" => ["class"]
          },
          set_tag_attribute_values: %{"input" => %{"aria-label" => "Task completed"}}
        ]
      )

    Enum.reduce(illustrations, html, fn {placeholder, figure}, rendered ->
      String.replace(rendered, "<p>#{placeholder}</p>", figure)
    end)
  end

  defp extract_illustrations(%MDEx.CodeBlock{info: info, literal: literal} = node, figures) do
    if info in Leitor.Illustration.languages() do
      placeholder = "LEITORILLUSTRATION" <> Base.encode16(:crypto.strong_rand_bytes(16))

      {%MDEx.Paragraph{nodes: [%MDEx.Text{literal: placeholder}]},
       [{placeholder, Leitor.Illustration.render(literal, info, node.closed)} | figures]}
    else
      {node, figures}
    end
  end

  defp extract_illustrations(%{nodes: nodes} = node, figures) do
    {nodes, figures} = Enum.map_reduce(nodes, figures, &extract_illustrations/2)
    {%{node | nodes: nodes}, figures}
  end

  defp extract_illustrations(node, figures), do: {node, figures}

  defp prose(%MDEx.CodeBlock{}), do: ""
  defp prose(%MDEx.HtmlBlock{}), do: ""
  defp prose(%MDEx.HtmlInline{}), do: ""
  defp prose(%{literal: literal}), do: String.replace(literal, "\u00A0", " ")

  defp prose(%{__struct__: module, nodes: nodes})
       when module in [MDEx.Document, MDEx.List, MDEx.ListItem, MDEx.TaskItem, MDEx.BlockQuote],
       do: Enum.map_join(nodes, " ", &prose/1)

  defp prose(%{nodes: nodes}), do: Enum.map_join(nodes, &prose/1)
  defp prose(_node), do: " "

  defp fragment(text, start, length), do: %{start: start, length: length, text: binary_part(text, start, length)}

  defp blocks(%{__struct__: module} = node) when module in [MDEx.Paragraph, MDEx.Heading], do: [node]
  defp blocks(%{nodes: nodes}), do: Enum.flat_map(nodes, &blocks/1)
  defp blocks(_node), do: []
end
