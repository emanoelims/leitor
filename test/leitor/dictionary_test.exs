defmodule Leitor.DictionaryTest do
  use Leitor.DataCase, async: false

  alias Leitor.Accounts.Preferences
  alias Leitor.Dictionary
  alias Leitor.Dictionary.Card
  alias ReqLLM.Message.ContentPart

  doctest Dictionary

  @card %{
    "meaning" => "  conduzir  ",
    "headword" => "run",
    "part_of_speech" => "verbo",
    "ipa" => "ˈrʌn",
    "explanation" => "Aqui significa conduzir a reunião.",
    "usage_note" => "",
    "forms" => ["runs", " ", "ran", "running", "run", "runs", "ran", "x"],
    "examples" => [
      %{"en" => "She runs the meeting.", "pt" => "Ela conduz a reunião."},
      %{"en" => "Who runs this place?", "pt" => "Quem comanda este lugar?"},
      %{"en" => "Extra.", "pt" => "Extra."},
      %{"en" => "Missing translation."}
    ],
    "other_senses" => [
      %{"part_of_speech" => "verbo", "gloss" => "correr", "translations" => ["correr"]},
      %{"part_of_speech" => "verbo", "gloss" => "funcionar", "translations" => ["funcionar", 1]},
      %{"part_of_speech" => "substantivo", "gloss" => "corrida", "translations" => []},
      %{"part_of_speech" => "substantivo", "gloss" => "temporada", "translations" => ["temporada"]}
    ]
  }

  setup do
    previous = Application.get_env(:leitor, :language_adapter)
    Application.put_env(:leitor, :language_adapter, Leitor.LanguageCapture)

    on_exit(fn ->
      if previous,
        do: Application.put_env(:leitor, :language_adapter, previous),
        else: Application.delete_env(:leitor, :language_adapter)
    end)

    blocks = [
      %{text: "The meeting started late."},
      %{text: "She ran the firm and ran the board."},
      %{text: "Everyone agreed."}
    ]

    %{blocks: blocks, request: Dictionary.request(blocks, 1, "ran", {21, 24})}
  end

  test "marks the selected occurrence and keeps the surrounding text", %{blocks: blocks, request: request} do
    assert request == %{
             selection: "ran",
             paragraph: "She ran the firm and ⟦ran⟧ the board.",
             text: "The meeting started late.\n\nShe ran the firm and ran the board.\n\nEveryone agreed."
           }

    assert Dictionary.request(blocks, 1, "ran", {0, 3}).paragraph == "She ⟦ran⟧ the firm and ran the board."
    assert Dictionary.request(blocks, 9, "ran") == {:error, :invalid_input}

    long = for i <- 1..40, do: %{text: "Block #{i} " <> String.duplicate("x", 1000)}
    window = Dictionary.request(long, 20, "Block 21").text
    assert String.length(window) <= 24_000
    assert window =~ "Block 21" and window =~ "Block 10" and window =~ "Block 32"
    refute window =~ "Block 1 "
  end

  test "asks Claude with cached instructions and page text, at low effort, and streams fragments", %{request: request} do
    Process.put(:language_result, {:ok, @card})
    Process.put(:language_fragments, [~s({"meaning": "condu)])
    test = self()

    assert {:ok, card} = Dictionary.lookup(request, nil, &send(test, {:fragment, &1}))

    assert_received {:fragment, ~s({"meaning": "condu)}
    assert_received {:language_options, [reasoning_effort: :low]}
    assert_received {:language_request, "anthropic:claude-sonnet-5-5", %ReqLLM.Context{messages: [system, user]}, schema}
    assert hd(schema.required) == "meaning"

    assert [%ContentPart{text: instructions, metadata: %{cache_control: %{type: "ephemeral"}}}] = system.content
    assert instructions =~ "⟦ ⟧"

    assert [%ContentPart{text: "Text being read:\n" <> _, metadata: %{cache_control: _}}, %ContentPart{text: selection}] =
             user.content

    assert selection =~ ~s(She ran the firm and ⟦ran⟧ the board.)

    assert card["meaning"] == "conduzir"
    assert card["forms"] == ["runs", "ran", "running", "run", "runs", "ran"]
    assert length(card["examples"]) == 2
    assert [_, %{"translations" => ["funcionar"]}, _] = card["other_senses"]
  end

  test "reuses cached cards and keys them by model", %{request: request} do
    Process.put(:language_result, {:ok, @card})
    assert {:ok, card} = Dictionary.lookup(request)
    assert_received {:language_request, _, _, _}

    Process.put(:language_result, {:error, :provider_error})
    assert Dictionary.lookup(request) == {:ok, card}
    refute_received {:language_request, _, _, _}
    assert [%Card{model: "anthropic:claude-sonnet-5-5"}] = Repo.all(Card)

    opus = %Preferences{reading_model: "anthropic:claude-opus-5-5"}
    assert Dictionary.lookup(request, opus) == {:error, :provider_error}
    assert_received {:language_request, "anthropic:claude-opus-5-5", _, _}
  end

  test "rejects invalid input and responses without caching them", %{request: request} do
    assert Dictionary.lookup(%{request | paragraph: "She ran the firm."}) == {:error, :invalid_input}
    assert Dictionary.lookup(%{request | selection: String.duplicate("a", 201)}) == {:error, :invalid_input}
    refute_received {:language_request, _, _, _}

    Process.put(:language_result, {:ok, %{"meaning" => " ", "explanation" => "x"}})
    assert Dictionary.lookup(request) == {:error, :invalid_response}
    Process.put(:language_result, {:ok, %{"answer" => "not a card"}})
    assert Dictionary.lookup(request) == {:error, :invalid_response}
    assert Repo.all(Card) == []
  end

  test "uses the reader's model, the configured model, or Sonnet" do
    assert Dictionary.model(%Preferences{reading_model: "anthropic:claude-haiku-5-5"}) == "anthropic:claude-haiku-5-5"
    assert Dictionary.model(%Preferences{reading_model: "default"}) == "anthropic:claude-sonnet-5-5"
    System.put_env("LEITOR_DICTIONARY_MODEL", "anthropic:claude-opus-5-5")
    on_exit(fn -> System.delete_env("LEITOR_DICTIONARY_MODEL") end)
    assert Dictionary.model(nil) == "anthropic:claude-opus-5-5"
  end

  test "renders escaped Markdown with a pronunciation hint, within the annotation limit" do
    card = %{
      "meaning" => "*negrito*",
      "headword" => "issue",
      "part_of_speech" => "substantivo",
      "ipa" => "/ˈɪʃu/",
      "explanation" => "Uma edição [da revista].",
      "usage_note" => "Formal.",
      "forms" => [],
      "examples" => [],
      "other_senses" => [%{"part_of_speech" => "substantivo", "gloss" => "problema", "translations" => []}]
    }

    markdown = Dictionary.markdown(card)
    assert markdown =~ "**\\*negrito\\***"
    assert markdown =~ "/ˈɪʃu/ · *pronúncia:* I-chu"
    assert markdown =~ "Uma edição \\[da revista\\]."
    assert markdown =~ "*Uso:* Formal."
    assert markdown =~ "- *(substantivo)* problema"
    refute markdown =~ "Formas"

    long = %{card | "explanation" => String.duplicate("a", 3800), "ipa" => ""}
    assert String.length(Dictionary.markdown(long)) <= 3900
    refute Dictionary.markdown(long) =~ "pronúncia"
  end
end
