defmodule Leitor.Dictionary.ImportTest do
  use Leitor.DataCase, async: false

  alias Leitor.Dictionary.Entry
  alias Leitor.Dictionary.Import

  doctest Import

  @tag :tmp_dir
  test "streams plain and gzip JSON Lines, keeping a final line without a newline", %{tmp_dir: dir} do
    content = ~s({"a":1}\n{"b":2}\n{"c":3})
    plain = Path.join(dir, "words.jsonl")
    gzip = Path.join(dir, "words.jsonl.gz")
    File.write!(plain, content)
    File.write!(gzip, :zlib.gzip(content))

    assert Enum.to_list(Import.lines(plain)) == [~s({"a":1}), ~s({"b":2}), ~s({"c":3})]
    assert Enum.to_list(Import.lines(gzip)) == [~s({"a":1}), ~s({"b":2}), ~s({"c":3})]
  end

  @tag :tmp_dir
  test "imports from a file or a downloaded URL through the mix task", %{tmp_dir: dir} do
    line =
      Jason.encode!(%{"word" => "go", "lang_code" => "en", "pos" => "verb", "senses" => [%{"glosses" => ["To move."]}]})

    path = Path.join(dir, "words.jsonl")
    File.write!(path, line <> "\n")

    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(Mix.Shell.IO) end)
    Mix.Tasks.Leitor.Dictionary.Import.run([path])
    assert_received {:mix_shell, :info, ["Imported 1 dictionary entries" <> _]}

    Req.Test.stub(Leitor.Dictionary, &Plug.Conn.send_resp(&1, 200, :zlib.gzip(line)))
    assert Import.import("https://example.test/words.jsonl.gz") == {:ok, 1}
    assert [%Entry{word: "go"}] = Repo.all(Entry)

    Req.Test.stub(Leitor.Dictionary, &Plug.Conn.send_resp(&1, 404, ""))
    assert Import.import("https://example.test/missing.jsonl") == {:error, {:http_status, 404}}

    assert_raise Mix.Error, ~r/failed/, fn ->
      Mix.Tasks.Leitor.Dictionary.Import.run(["https://example.test/missing.jsonl"])
    end

    assert_raise Mix.Error, ~r/Usage/, fn -> Mix.Tasks.Leitor.Dictionary.Import.run([]) end
  end

  test "replaces existing entries and skips unusable lines" do
    Repo.insert_all(Entry, [%{word: "old", key: "old", part_of_speech: "noun"}])

    lines = [
      Jason.encode!(%{
        "word" => "take off",
        "lang_code" => "en",
        "pos" => "verb",
        "forms" => [
          %{"form" => "took off", "tags" => ["past"]},
          %{"form" => "-"},
          %{"form" => "tooken off", "tags" => ["nonstandard"]}
        ],
        "translations" => [%{"code" => "pt", "word" => "decolar", "sense" => "to begin flight"}],
        "senses" => [
          %{
            "glosses" => ["To remove."],
            "examples" => [
              %{"text" => "Take off your shoes."},
              %{"text" => String.duplicate("x", 200), "type" => "example"}
            ],
            "translations" => [
              %{"code" => "pt", "word" => "tirar", "sense" => "to remove"},
              %{"code" => "pt", "word" => "decolar", "sense" => "to begin flight"},
              %{"code" => "pt", "word" => "levantar voo", "sense" => "to begin flight"},
              %{"code" => "es", "word" => "despegar", "sense" => "to begin flight"},
              %{"code" => "pt", "word" => "descolar", "sense" => "to begin flight", "tags" => ["Portugal"]}
            ]
          },
          %{"glosses" => ["To remove."]},
          %{"raw_glosses" => ["no glosses"]}
        ]
      }),
      Jason.encode!(%{
        "word" => "laufen",
        "lang_code" => "de",
        "pos" => "verb",
        "senses" => [%{"glosses" => ["to run"]}]
      }),
      Jason.encode!(%{"word" => "empty", "lang_code" => "en", "pos" => "noun", "senses" => []}),
      "not json"
    ]

    assert Import.run(lines) == 1

    assert [entry] = Repo.all(Entry)

    assert %Entry{word: "take off", key: "take off", part_of_speech: "verb", ipa: nil, forms: ["took off"], form_of: []} =
             entry

    assert entry.senses == [%{"gloss" => "To remove.", "example" => nil}]

    assert entry.translations == [
             %{"sense" => "to begin flight", "words" => ["decolar", "levantar voo"]},
             %{"sense" => "to remove", "words" => ["tirar"]}
           ]
  end
end
