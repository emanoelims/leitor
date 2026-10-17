defmodule Leitor.Illustration.SVG do
  @moduledoc "Validates bounded vector artwork and reconstructs SVG with isolated local identifiers. Scripts, HTML, styles, animation code and network references are never accepted."
  @tags ~w(svg g path rect circle ellipse line polyline polygon text tspan title desc defs linearGradient radialGradient stop clipPath)
  @attributes ~w(id viewBox width height x y x1 x2 y1 y2 cx cy r rx ry d points fill stroke stroke-width stroke-linecap stroke-linejoin stroke-dasharray stroke-dashoffset fill-rule opacity fill-opacity stroke-opacity transform font-size font-family font-weight text-anchor dominant-baseline dx dy gradientUnits gradientTransform offset stop-color stop-opacity fx fy spreadMethod clip-path clipPathUnits preserveAspectRatio vector-effect stroke-miterlimit font-style letter-spacing word-spacing textLength lengthAdjust paint-order)
  @typedoc "Reconstructed artwork, inert image source, intrinsic dimensions, and isolated identifiers."
  @type t :: %{
          markup: String.t(),
          src: String.t(),
          width: pos_integer(),
          height: pos_integer(),
          title: String.t(),
          ids: %{String.t() => String.t()}
        }

  @doc "Parses up to 64 KB/1,200 vector nodes and returns reconstructed artwork. Local gradient and clipping references must resolve within this SVG."
  @spec prepare(term()) :: {:ok, t()} | {:error, :invalid_svg}
  def prepare(source) when is_binary(source) and byte_size(source) <= 65_536 do
    with {:ok, root} <- parse(source),
         :ok <- validate(root) do
      build(root)
    end
  end

  def prepare(_), do: {:error, :invalid_svg}

  defp parse(source) do
    if String.valid?(source) and not Regex.match?(~r/<(?:\?|!(?!--))/, source) do
      case source |> LazyHTML.from_fragment() |> LazyHTML.to_tree(skip_whitespace_nodes: true) do
        [{"svg", _, _} = root] -> {:ok, root}
        _ -> {:error, :invalid_svg}
      end
    else
      {:error, :invalid_svg}
    end
  end

  defp validate({"svg", attrs, _} = root) do
    nodes = flatten(root)
    ids = for {tag, attrs, _} <- nodes, {"id", id} <- attrs, do: {id, tag}
    id_types = Map.new(ids)

    valid? =
      valid_node?(root, 0, false) and length(nodes) <= 1200 and length(ids) == map_size(id_types) and
        valid_dimensions?(attrs) and Enum.all?(nodes, &valid_references?(&1, id_types))

    if valid?, do: :ok, else: {:error, :invalid_svg}
  end

  defp valid_node?({:comment, _}, _, _), do: true
  defp valid_node?(text, _, _) when is_binary(text), do: true

  defp valid_node?({tag, attrs, children}, depth, clipped?) when tag in @tags and depth < 24 do
    in_clip? = clipped? or tag == "clipPath"
    Enum.all?(attrs, &valid_attribute?(&1, tag, in_clip?)) and Enum.all?(children, &valid_node?(&1, depth + 1, in_clip?))
  end

  defp valid_node?(_, _, _), do: false
  defp valid_attribute?({"xmlns", "http://www.w3.org/2000/svg"}, tag, _), do: tag == "svg"
  defp valid_attribute?({"id", value}, _, _), do: Regex.match?(~r/^[A-Za-z][A-Za-z0-9_-]{0,80}$/, value)
  defp valid_attribute?({"clip-path", _}, _, true), do: false

  defp valid_attribute?({name, value}, _, _) do
    name in @attributes and byte_size(value) <= 32_768 and
      not Regex.match?(~r/[<>\\\x00-\x08\x0b\x0c\x0e-\x1f]|var\s*\(|javascript\s*:|https?\s*:/i, value)
  end

  defp valid_references?({_tag, attrs, _}, ids) do
    Enum.all?(attrs, fn {name, value} ->
      if Regex.match?(~r/url\s*\(/i, value), do: valid_reference?(name, value, ids), else: true
    end)
  end

  defp valid_reference?(name, value, ids) do
    case Regex.run(~r/^url\(#([A-Za-z][A-Za-z0-9_-]{0,80})\)$/, value) do
      [_, id] when name in ~w(fill stroke) -> Map.get(ids, id) in ~w(linearGradient radialGradient)
      [_, id] when name == "clip-path" -> Map.get(ids, id) == "clipPath"
      _ -> false
    end
  end

  defp valid_dimensions?(attrs) do
    with {_, viewbox} <- List.keyfind(attrs, "viewBox", 0),
         [x, y, w, h] <- Regex.split(~r/[\s,]+/, String.trim(viewbox)),
         [{_, ""}, {_, ""}, {width, ""}, {height, ""}] <- Enum.map([x, y, w, h], &Float.parse/1) do
      width >= 1 and width <= 4096 and height >= 1 and height <= 4096
    else
      _ -> false
    end
  end

  defp build({"svg", attrs, children} = root) do
    {_, viewbox} = List.keyfind(attrs, "viewBox", 0)
    [_, _, w, h] = Regex.split(~r/[\s,]+/, String.trim(viewbox))
    {width, ""} = Float.parse(w)
    {height, ""} = Float.parse(h)
    prefix = "i" <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower) <> "-"
    ids = for {_, attrs, _} <- flatten(root), {"id", id} <- attrs, into: %{}, do: {id, prefix <> id}
    dimensions = [{"xmlns", "http://www.w3.org/2000/svg"}, {"width", to_string(width)}, {"height", to_string(height)}]
    markup = encode({"svg", dimensions ++ Enum.reject(attrs, &(elem(&1, 0) in ~w(xmlns width height))), children}, ids)
    title = root |> text_of_title() |> String.slice(0, 300)

    {:ok,
     %{
       markup: markup,
       src: "data:image/svg+xml;base64," <> Base.encode64(markup),
       width: round(width),
       height: round(height),
       title: title,
       ids: ids
     }}
  end

  defp flatten({:comment, _}), do: []
  defp flatten(text) when is_binary(text), do: []
  defp flatten({_, _, children} = node), do: [node | Enum.flat_map(children, &flatten/1)]

  defp text_of_title(root) do
    root |> flatten() |> Enum.filter(&(elem(&1, 0) == "title")) |> Enum.map_join(" ", &text/1)
  end

  defp text({:comment, _}), do: ""
  defp text(value) when is_binary(value), do: value
  defp text({_, _, children}), do: Enum.map_join(children, &text/1)
  defp encode({:comment, _}, _), do: ""
  defp encode(value, _) when is_binary(value), do: escape(value)

  defp encode({tag, attrs, children}, ids) do
    "<#{tag}" <>
      Enum.map_join(attrs, fn {name, value} -> ~s( #{name}="#{escape(rewrite(name, value, ids))}") end) <>
      ">" <> Enum.map_join(children, &encode(&1, ids)) <> "</#{tag}>"
  end

  defp rewrite("id", value, ids), do: Map.fetch!(ids, value)

  defp rewrite(_name, value, ids) do
    Regex.replace(~r/url\(#([A-Za-z][A-Za-z0-9_-]{0,80})\)/, value, fn _, id -> "url(##{Map.fetch!(ids, id)})" end)
  end

  defp escape(value), do: value |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()
end
