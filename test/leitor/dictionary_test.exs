defmodule Leitor.DictionaryTest do
  use ExUnit.Case, async: false

  alias Leitor.Dictionary

  doctest Dictionary

  @wiktionary %{
    "en" => [
      %{
        "partOfSpeech" => "Verb",
        "language" => "English",
        "definitions" => [
          %{
            "definition" =>
              ~s(To move <a rel="mw:WikiLink" href="/wiki/swiftly">swiftly</a>.\n<ol><li>A nested sense.</li></ol>),
            "parsedExamples" => [%{"example" => "<b>Run</b>, and you might catch the train&#33;"}]
          },
          %{"definition" => "To <i>manage</i> &amp; direct.", "examples" => ["She <b>runs</b> a shop."]},
          %{"definition" => ~s(<span class="usage-label-sense"></span>)},
          %{"definition" => "To operate.", "examples" => ["She <b>runs</b> a shop."]},
          %{"definition" => "A fourth sense."}
        ]
      },
      %{"partOfSpeech" => "Symbol", "language" => "Translingual", "definitions" => [%{"definition" => "A code."}]},
      %{"partOfSpeech" => "Noun", "language" => "English", "definitions" => [%{"definition" => "An act of running."}]},
      %{"partOfSpeech" => "Verb", "definitions" => [%{"definition" => "Merged later."}]}
    ],
    "nl" => [%{"partOfSpeech" => "Noun", "definitions" => [%{"definition" => "Ignored."}]}]
  }

  @pronunciation [
    %{
      "phonetics" => [
        %{"text" => "/ɹʌn/", "audio" => "http://insecure.example/run.mp3"},
        %{"audio" => "https://api.dictionaryapi.dev/media/pronunciations/en/run-au.mp3"},
        %{"audio" => "https://api.dictionaryapi.dev/media/pronunciations/en/run-us.mp3"}
      ]
    }
  ]

  setup do
    previous = Application.get_env(:leitor, Dictionary)
    on_exit(fn -> Application.put_env(:leitor, Dictionary, previous) end)
    :ok
  end

  defp stub(deepl, wiktionary, pronunciation \\ &Plug.Conn.send_resp(&1, 404, "")) do
    test = self()

    Req.Test.stub(Dictionary, fn conn ->
      case conn.host do
        "en.wiktionary.org" ->
          send(test, {:wiktionary, conn.request_path, Plug.Conn.get_req_header(conn, "user-agent")})
          wiktionary.(conn)

        "api.dictionaryapi.dev" ->
          send(test, {:pronunciation, conn.request_path})
          pronunciation.(conn)

        host ->
          {:ok, body, conn} = Plug.Conn.read_body(conn)
          send(test, {:deepl, host, Plug.Conn.get_req_header(conn, "authorization"), Jason.decode!(body)})
          deepl.(conn)
      end
    end)
  end

  defp translated(text), do: &Req.Test.json(&1, %{"translations" => [%{"text" => text}]})
  defp status(code), do: &Plug.Conn.send_resp(&1, code, "")

  test "combines a contextual translation, English senses and pronunciation" do
    stub(translated("dirigir"), &Req.Test.json(&1, @wiktionary), &Req.Test.json(&1, @pronunciation))

    assert {:ok, entry} = Dictionary.lookup(" Run, ", "She will run the company.")

    assert entry.term == "Run"
    assert entry.translation == "dirigir"
    assert entry.phonetic == "/ɹʌn/"
    assert entry.audio == "https://api.dictionaryapi.dev/media/pronunciations/en/run-us.mp3"

    assert entry.meanings == [
             %{
               part_of_speech: "verb",
               senses: [
                 %{definition: "To move swiftly.", example: "Run, and you might catch the train!"},
                 %{definition: "To manage & direct.", example: "She runs a shop."},
                 %{definition: "To operate.", example: nil}
               ]
             },
             %{part_of_speech: "noun", senses: [%{definition: "An act of running.", example: nil}]}
           ]

    assert_received {:wiktionary, "/api/rest_v1/page/definition/run", ["Leitor/" <> _]}
    assert_received {:pronunciation, "/api/v2/entries/en/run"}

    assert_received {:deepl, "api-free.deepl.com", ["DeepL-Auth-Key test-key:fx"],
                     %{"text" => ["Run"], "target_lang" => "PT-BR", "context" => "She will run the company."}}

    assert Dictionary.markdown(entry) =~ "**dirigir** · /ɹʌn/\n\n*verb*\n\n1. To move swiftly. — *Run, and"
    assert Dictionary.markdown(entry) =~ "\n\n*noun*\n\n1. An act of running."
  end

  test "keeps a translation without senses and skips long phrases" do
    stub(translated("decolar"), status(404))
    assert {:ok, %{translation: "decolar", meanings: [], audio: nil}} = Dictionary.lookup("take off", "")
    assert_received {:wiktionary, "/api/rest_v1/page/definition/take_off", _agent}
    refute_received {:pronunciation, _path}

    stub(translated("um pouco mais longo"), status(500))
    assert {:ok, %{translation: "um pouco mais longo"}} = Dictionary.lookup("a bit longer than this", "")
    refute_received {:wiktionary, _path, _agent}
  end

  test "uses the paid DeepL host and works without a DeepL key" do
    Application.put_env(
      :leitor,
      Dictionary,
      Keyword.put(Application.get_env(:leitor, Dictionary), :deepl_api_key, "paid")
    )

    stub(translated("correr"), status(404))
    assert {:ok, %{translation: "correr"}} = Dictionary.lookup("run", "")
    assert_received {:deepl, "api.deepl.com", ["DeepL-Auth-Key paid"], _body}

    Application.put_env(:leitor, Dictionary, Keyword.delete(Application.get_env(:leitor, Dictionary), :deepl_api_key))
    stub(status(500), &Req.Test.json(&1, @wiktionary))
    assert {:ok, %{translation: nil, meanings: [_, _]} = entry} = Dictionary.lookup("run", "")
    refute_received {:deepl, _host, _auth, _body}
    assert Dictionary.markdown(%{entry | meanings: []}) == "**run**"
  end

  test "distinguishes unknown terms from unavailable providers" do
    stub(translated("xqzv"), status(404))
    assert Dictionary.lookup("xqzv", "") == {:error, :not_found}

    stub(translated("xqzv"), &Req.Test.json(&1, %{"nl" => []}))
    assert Dictionary.lookup("xqzv", "") == {:error, :not_found}

    stub(status(456), status(500), &Req.Test.json(&1, @pronunciation))
    assert Dictionary.lookup("run", "") == {:error, :unavailable}

    stub(translated(""), &Req.Test.json(&1, ["unexpected"]))
    assert Dictionary.lookup("run", "") == {:error, :unavailable}

    assert Dictionary.lookup(String.duplicate("a", 201), "") == {:error, :invalid_input}
  end

  test "retries intermittent gateway errors but not missing entries" do
    {:ok, attempts} = Agent.start_link(fn -> 0 end)

    stub(status(456), fn conn ->
      case Agent.get_and_update(attempts, &{&1, &1 + 1}) do
        0 -> Plug.Conn.send_resp(conn, 522, "")
        _ -> Req.Test.json(conn, @wiktionary)
      end
    end)

    assert {:ok, %{meanings: [_, _]}} = Dictionary.lookup("run", "")
    assert Agent.get(attempts, & &1) == 2

    {:ok, missing} = Agent.start_link(fn -> 0 end)

    stub(status(456), fn conn ->
      Agent.update(missing, &(&1 + 1))
      Plug.Conn.send_resp(conn, 404, "")
    end)

    assert Dictionary.lookup("run", "") == {:error, :unavailable}
    assert Agent.get(missing, & &1) == 1
  end

  test "escapes Markdown structure in dictionary text" do
    entry = %{
      term: "x",
      translation: "*a* [b]",
      phonetic: nil,
      audio: nil,
      meanings: [%{part_of_speech: "noun", senses: [%{definition: "# not_a heading", example: nil}]}]
    }

    assert Dictionary.markdown(entry) == "**\\*a\\* \\[b\\]**\n\n*noun*\n\n1. \\# not\\_a heading"
  end
end
