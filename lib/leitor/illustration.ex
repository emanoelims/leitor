defmodule Leitor.Illustration do
  @moduledoc "Validated artwork fences. Legacy scenes use application-owned motion; program figures contain only private artifact references and execute in a separate sandbox."
  alias Leitor.Illustration.Scene
  alias Leitor.Illustration.SVG

  @languages ~w(leitor-svg leitor-svg-float leitor-svg-sway leitor-svg-pulse leitor-scene leitor-figure)
  @doc "Returns recognized illustration and scene fence identifiers."
  @spec languages() :: [String.t()]
  def languages, do: @languages
  @doc "Returns a validated, inert SVG image data URI; invalid or active markup returns an error."
  @spec image(term()) :: {:ok, String.t()} | {:error, :invalid_svg}
  def image(source) do
    with {:ok, svg} <- SVG.prepare(source), do: {:ok, svg.src}
  end

  @doc "Renders safe artwork or a loading/unavailable state. Scenes animate named vector layers with bounded app-owned primitives."
  @spec render(String.t(), String.t()) :: String.t()
  @spec render(String.t(), String.t(), boolean()) :: String.t()
  def render(source, language, complete? \\ true) when language in @languages do
    case artwork(source, language) do
      {:ok, figure} ->
        key = :sha256 |> :crypto.hash(language <> source) |> Base.encode16(case: :lower)
        String.replace_prefix(figure, "<figure ", ~s(<figure data-artwork-key="#{key}" ))

      {:error, _} when not complete? ->
        ~s(<figure class="page-illustration is-drawing" role="status" aria-label="#{escape(Gettext.gettext(LeitorWeb.Gettext, "Drawing illustration…"))}"><span></span><span></span><span></span></figure>)

      {:error, _} ->
        ~s(<figure class="page-illustration is-unavailable" role="status">#{escape(Gettext.gettext(LeitorWeb.Gettext, "Illustration unavailable"))}</figure>)
    end
  end

  @doc "Rejects unsafe or incomplete generated artwork before it becomes final AI output. Ordinary code remains untouched."
  @spec valid_markdown?(String.t()) :: boolean()
  def valid_markdown?(markdown), do: markdown |> MDEx.parse_document!() |> valid_blocks?()

  @doc "Requires at least one complete, validated artwork block for a requested illustrated format. Prose alone cannot satisfy a visual generation."
  @spec valid_visual_markdown?(String.t()) :: boolean()
  def valid_visual_markdown?(markdown) do
    document = MDEx.parse_document!(markdown)
    valid_blocks?(document) and artwork_block?(document)
  end

  defp artwork_block?(%MDEx.CodeBlock{info: info}), do: info in @languages
  defp artwork_block?(%{nodes: nodes}), do: Enum.any?(nodes, &artwork_block?/1)
  defp artwork_block?(_), do: false

  defp artwork(source, "leitor-figure") do
    with {:ok, blueprint} <- Leitor.Figures.decode(source) do
      title = escape(blueprint.title)
      caption = escape(blueprint.caption)
      data = blueprint |> Jason.encode!() |> escape()

      {:ok,
       ~s(<figure class="page-illustration leitor-figure iso" data-figure="#{data}"><header class="figure-heading"><span>FIG. 01</span><strong>#{title}</strong></header><div class="figure-stage" tabindex="0" role="group" aria-label="#{title}"></div><div class="figure-controls"></div><figcaption>#{caption}</figcaption></figure>)}
    end
  end

  defp artwork(source, "leitor-scene") do
    with {:ok, scene} <- Scene.from_json(source),
         {:ok, svg} <- SVG.prepare(scene.svg) do
      motion = scene |> Scene.animations(svg) |> Jason.encode!() |> escape()
      control = if scene.animations == [], do: "", else: control()

      {:ok,
       ~s(<figure class="page-illustration page-scene" data-scene="#{motion}" data-paused="false"><div class="scene-art" role="img" aria-label="#{escape(svg.title)}" style="aspect-ratio:#{svg.width}/#{svg.height}">#{svg.markup}</div>#{control}</figure>)}
    end
  end

  defp artwork(source, language) do
    with {:ok, svg} <- SVG.prepare(source) do
      motion = language |> String.replace_prefix("leitor-svg", "") |> String.trim_leading("-")
      control = if motion == "", do: "", else: control()
      title = if svg.title == "", do: Gettext.gettext(LeitorWeb.Gettext, "SVG illustration"), else: svg.title

      {:ok,
       ~s(<figure class="page-illustration" data-motion="#{motion}" data-paused="false"><img src="#{svg.src}" width="#{svg.width}" height="#{svg.height}" alt="#{escape(title)}" decoding="async">#{control}</figure>)}
    end
  end

  defp control,
    do:
      ~s(<button type="button" data-illustration-toggle aria-pressed="false">#{escape(Gettext.gettext(LeitorWeb.Gettext, "Pause animation"))}</button>)

  defp valid_blocks?(%MDEx.CodeBlock{info: info, literal: source, closed: closed}) when info in @languages do
    closed and match?({:ok, _}, artwork(source, info))
  end

  defp valid_blocks?(%{nodes: nodes}), do: Enum.all?(nodes, &valid_blocks?/1)
  defp valid_blocks?(_), do: true
  defp escape(value), do: value |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()
end
