defmodule LeitorWeb.DictionaryComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias LeitorWeb.DictionaryComponents

  @card %{
    "meaning" => "conseguiu realizar",
    "headword" => "pull off",
    "part_of_speech" => "verbo frasal",
    "ipa" => "ˌpʊl ˈɔf",
    "explanation" => "Indica que ela conseguiu fazer o lançamento dar certo.",
    "usage_note" => "Informal.",
    "forms" => ["pulls off", "pulled off"],
    "examples" => [%{"en" => "Nobody thought he could pull it off.", "pt" => "Ninguém achava que ele conseguiria."}],
    "other_senses" => [
      %{"part_of_speech" => "verbo frasal", "gloss" => "tirar algo puxando", "translations" => ["arrancar"]}
    ]
  }

  defp text(document, selector), do: document |> LazyHTML.query(selector) |> LazyHTML.text() |> String.trim()

  test "shows the meaning, pronunciation and explanation first and folds the details" do
    document =
      (&DictionaryComponents.card/1)
      |> render_component(id: "card", card: @card, quote: "pulled off")
      |> LazyHTML.from_fragment()

    assert text(document, "#card .dictionary-meaning") == "conseguiu realizar"
    assert text(document, ".dictionary-meta") == "pull off · verbo frasal"
    assert text(document, ".dictionary-hint") == "pul ÓF"
    assert text(document, ".dictionary-ipa") == "/ˌpʊl ˈɔf/"
    assert text(document, ".dictionary-usage") == "Informal."
    assert LazyHTML.attribute(LazyHTML.query(document, "details.dictionary-more"), "open") == []
    assert text(document, ".dictionary-examples [lang=en]") == "Nobody thought he could pull it off."
    assert text(document, ".dictionary-forms") =~ "pulls off"
    assert text(document, ".dictionary-senses") =~ "tirar algo puxando → arrancar"
  end

  test "omits a headword equal to the selection and empty sections" do
    card = %{@card | "headword" => "Pull off", "usage_note" => "", "forms" => [], "examples" => [], "other_senses" => []}

    document =
      (&DictionaryComponents.card/1)
      |> render_component(id: "card", card: card, quote: "pull off")
      |> LazyHTML.from_fragment()

    assert text(document, ".dictionary-meta") == "verbo frasal"
    assert document |> LazyHTML.query(".dictionary-usage") |> Enum.empty?()
    assert document |> LazyHTML.query("details") |> Enum.empty?()
  end

  test "previews the streamed meaning in the card's style" do
    html = render_component(&DictionaryComponents.meaning_preview/1, meaning: "conduzia")
    assert text(LazyHTML.from_fragment(html), ".dictionary-meaning") == "conduzia"
  end
end
