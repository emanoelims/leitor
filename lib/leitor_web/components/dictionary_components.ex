defmodule LeitorWeb.DictionaryComponents do
  @moduledoc """
  Renders dictionary cards in reader margins: the meaning and pronunciation
  first, then the explanation and usage note, with examples, forms and other
  senses folded away. Marks saved before cards were stored keep rendering their
  Markdown body.
  """
  use LeitorWeb, :html

  alias Leitor.Dictionary.Pronunciation

  attr :card, :map, required: true, doc: "a validated `Leitor.Dictionary` card"
  attr :quote, :string, required: true, doc: "the selected text, to omit a headword that repeats it"
  attr :id, :string, required: true

  def card(assigns) do
    card = assigns.card

    assigns =
      assign(assigns,
        meaning: card["meaning"],
        meta: meta(card, assigns.quote),
        hint: Pronunciation.respell(card["ipa"] || ""),
        ipa: ipa(card["ipa"]),
        explanation: card["explanation"],
        usage: card["usage_note"] || "",
        examples: card["examples"] || [],
        forms: card["forms"] || [],
        senses: card["other_senses"] || []
      )

    ~H"""
    <div id={@id} class="dictionary-card">
      <div class="dictionary-head">
        <div class="dictionary-entry">
          <p class="dictionary-meaning"><span>{@meaning}</span></p>
          <p :if={@meta != ""} class="dictionary-meta">{@meta}</p>
        </div>
        <p :if={@hint != ""} class="dictionary-say" aria-label={gettext("Pronunciation")}>
          <span class="dictionary-hint">{@hint}</span><span class="dictionary-ipa">{@ipa}</span>
        </p>
      </div>
      <p class="dictionary-explanation">{@explanation}</p>
      <p :if={@usage != ""} class="dictionary-usage">{@usage}</p>
      <details :if={@examples != [] or @forms != [] or @senses != []} class="dictionary-more">
        <summary>
          <.icon name="lucide-chevron-down" class="size-3.5" />{gettext(
            "Examples, forms and other senses"
          )}
        </summary>
        <ul :if={@examples != []} class="dictionary-examples">
          <li :for={example <- @examples}>
            <span lang="en">{example["en"]}</span><span>{example["pt"]}</span>
          </li>
        </ul>
        <ul :if={@forms != []} class="dictionary-forms" lang="en">
          <li :for={form <- @forms}>{form}</li>
        </ul>
        <ul :if={@senses != []} class="dictionary-senses">
          <li :for={sense <- @senses}>
            <small>{sense["part_of_speech"]}</small> {sense["gloss"]}<span :if={
              (sense["translations"] || []) != []
            }> → {Enum.join(sense["translations"], ", ")}</span>
          </li>
        </ul>
      </details>
    </div>
    """
  end

  attr :meaning, :string, required: true

  @doc "The meaning shown while the rest of a card is still being written."
  def meaning_preview(assigns) do
    ~H"""
    <div class="dictionary-card">
      <p class="dictionary-meaning"><span>{@meaning}</span></p>
    </div>
    """
  end

  defp meta(card, quote) do
    headword = card["headword"] || ""
    headword = if normalize(headword) == normalize(quote), do: "", else: headword
    [headword, card["part_of_speech"] || ""] |> Enum.reject(&(&1 == "")) |> Enum.join(" · ")
  end

  defp normalize(text), do: text |> String.trim() |> String.downcase()

  defp ipa(nil), do: ""
  defp ipa(""), do: ""
  defp ipa(ipa), do: "/" <> String.trim(ipa, "/") <> "/"
end
