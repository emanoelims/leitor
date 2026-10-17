defmodule Leitor.DictionaryTest do
  use Leitor.DataCase, async: false

  import Leitor.DictionaryFixtures

  alias Leitor.Dictionary

  doctest Dictionary

  setup do
    dictionary_fixture()
    previous = Application.get_env(:leitor, Dictionary)
    on_exit(fn -> Application.put_env(:leitor, Dictionary, previous) end)
    :ok
  end

  defp configure(options),
    do: Application.put_env(:leitor, Dictionary, Keyword.merge(Application.get_env(:leitor, Dictionary), options))

  defp stub(deepl, azure \\ &Plug.Conn.send_resp(&1, 500, "")) do
    test = self()

    Req.Test.stub(Dictionary, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(test, {conn.host, conn.request_path, conn.query_string, conn.req_headers, Jason.decode!(body)})
      if conn.host == "api.cognitive.microsofttranslator.com", do: azure.(conn), else: deepl.(conn)
    end)
  end

  defp translated(text), do: &Req.Test.json(&1, %{"translations" => [%{"text" => text}]})
  defp status(code), do: &Plug.Conn.send_resp(&1, code, "")

  defp azure_examples(conn) do
    case conn.request_path do
      "/dictionary/lookup" ->
        Req.Test.json(conn, [
          %{
            "normalizedSource" => "run",
            "translations" => [%{"normalizedTarget" => "correr"}, %{"normalizedTarget" => "dirigir"}]
          }
        ])

      "/dictionary/examples" ->
        Req.Test.json(conn, [
          %{
            "examples" => [
              %{
                "sourcePrefix" => "I have a hospital to ",
                "sourceTerm" => "run",
                "sourceSuffix" => ".",
                "targetPrefix" => "Eu tenho um hospital para ",
                "targetTerm" => "dirigir",
                "targetSuffix" => "."
              },
              %{"sourcePrefix" => "incomplete"}
            ]
          }
        ])
    end
  end

  test "highlights the passage's meaning and adds bilingual examples" do
    configure(azure_translator_key: "azure-key", azure_translator_region: "brazilsouth")
    stub(translated("dirigir"), &azure_examples/1)

    assert {:ok, entry} = Dictionary.lookup(" run, ", "She will run the company.")

    assert entry.translation == "dirigir"
    assert entry.phonetic == "/ɹʌn/"
    assert entry.forms == ["runs", "ran"]
    assert entry.context == %{part_of_speech: "verb", sense: "to be in charge of", words: ["dirigir", "gerir"]}

    assert [%{source: %{term: "run"}, target: %{prefix: "Eu tenho um hospital para ", term: "dirigir"}}] =
             entry.examples

    assert entry.parts == [
             %{
               part_of_speech: "verb",
               groups: [%{sense: "to move quickly", words: ["correr"]}],
               senses: [%{definition: "To move swiftly.", example: nil}]
             },
             %{part_of_speech: "adjective", groups: [], senses: [%{definition: "Melted.", example: "Run *butter*."}]}
           ]

    assert_received {"api-free.deepl.com", "/v2/translate", _, headers,
                     %{"text" => ["run"], "target_lang" => "PT-BR", "context" => "She will run the company."}}

    assert {"authorization", "DeepL-Auth-Key test-key:fx"} in headers
    assert_received {"api.cognitive.microsofttranslator.com", "/dictionary/lookup", query, headers, [%{"Text" => "run"}]}
    assert query =~ "from=en" and query =~ "to=pt"
    assert {"ocp-apim-subscription-region", "brazilsouth"} in headers
    assert_received {_, "/dictionary/examples", _, _, [%{"Text" => "run", "Translation" => "dirigir"}]}

    markdown = Dictionary.markdown(entry)
    assert markdown =~ "**dirigir** · /ɹʌn/\n\n*Forms:* runs, ran\n\n**In this passage** · *verb* · *to be in charge of*"
    assert markdown =~ "- I have a hospital to **run**. → Eu tenho um hospital para **dirigir**."
    assert markdown =~ "1. Melted. — *Run \\*butter\\*.*"
    assert Dictionary.meaning(entry) == "dirigir"
    assert Dictionary.part_of_speech(entry) == "verb"
  end

  test "resolves inflections and works from the local dictionary alone" do
    configure(deepl_api_key: nil)
    stub(status(500))

    assert {:ok, entry} = Dictionary.lookup("ran", "He ran home.")
    assert %{translation: nil, lemma: "run", note: "simple past of run", context: nil, examples: []} = entry
    assert [%{part_of_speech: "verb", groups: [_, _]}, %{part_of_speech: "adjective"}] = entry.parts
    refute_received {_, _, _, _, _}

    assert Dictionary.markdown(entry) =~ "**correr** · /ɹʌn/\n\n*simple past of run*"
    assert Dictionary.meaning(entry) == "correr"
    assert Dictionary.part_of_speech(entry) == "verb"
  end

  test "keeps DeepL alone for unknown words and skips Azure examples without a matching translation" do
    configure(azure_translator_key: "azure-key")
    stub(translated("por acaso"), &azure_examples/1)

    assert {:ok, %{translation: "por acaso", parts: [], context: nil, examples: []} = entry} =
             Dictionary.lookup("serendipitously", "")

    refute_received {_, "/dictionary/examples", _, _, _}
    assert Dictionary.markdown(entry) == "**por acaso**"
    assert Dictionary.meaning(entry) == "por acaso"
    assert Dictionary.part_of_speech(entry) == nil
  end

  test "reports unknown terms, unavailable providers and invalid input" do
    stub(translated("xqzv"))
    assert Dictionary.lookup("xqzv", "") == {:error, :not_found}

    stub(status(456))
    assert Dictionary.lookup("xqzv", "") == {:error, :unavailable}

    configure(deepl_api_key: "paid")
    stub(status(503))
    assert {:ok, %{translation: nil, parts: [_ | _]}} = Dictionary.lookup("run", "")
    assert_received {"api.deepl.com", _, _, _, _}

    assert Dictionary.lookup(String.duplicate("a", 201), "") == {:error, :invalid_input}
  end

  test "retries DeepL gateway errors" do
    {:ok, attempts} = Agent.start_link(fn -> 0 end)

    stub(fn conn ->
      case Agent.get_and_update(attempts, &{&1, &1 + 1}) do
        0 -> Plug.Conn.send_resp(conn, 522, "")
        _ -> Req.Test.json(conn, %{"translations" => [%{"text" => "maravilhoso"}]})
      end
    end)

    assert {:ok, %{translation: "maravilhoso", context: %{sense: "excellent"}}} = Dictionary.lookup("wonderful", "")
    assert Agent.get(attempts, & &1) == 2
  end

  test "keeps Markdown within the annotation limit" do
    group = %{sense: String.duplicate("s", 100), words: [String.duplicate("w", 100)]}
    parts = for _ <- 1..30, do: %{part_of_speech: "noun", groups: [group], senses: []}

    entry = %{
      term: "x",
      translation: nil,
      lemma: nil,
      note: nil,
      phonetic: nil,
      forms: [],
      context: nil,
      examples: [],
      parts: parts
    }

    markdown = Dictionary.markdown(entry)
    assert String.length(markdown) <= 3900
    assert markdown =~ "**#{String.duplicate("w", 100)}**"
  end
end
