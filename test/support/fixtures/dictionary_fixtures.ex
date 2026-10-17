defmodule Leitor.DictionaryFixtures do
  @moduledoc false

  alias Leitor.Dictionary.Import

  @entries [
    %{
      "word" => "run",
      "lang_code" => "en",
      "pos" => "verb",
      "sounds" => [%{"ipa" => "/ɹʌn/"}],
      "forms" => [
        %{"form" => "runs", "tags" => ["present"]},
        %{"form" => "ran", "tags" => ["past"]},
        %{"form" => "runnest", "tags" => ["archaic", "second-person"]}
      ],
      "senses" => [
        %{
          "glosses" => ["To move swiftly."],
          "translations" => [
            %{"code" => "pt", "word" => "correr", "sense" => "to move quickly"},
            %{"code" => "pt", "word" => "dirigir", "sense" => "to be in charge of"},
            %{"code" => "pt", "word" => "gerir", "sense" => "to be in charge of"},
            %{"code" => "pt", "word" => "gerenciar", "sense" => "to be in charge of", "tags" => ["Portugal"]}
          ]
        }
      ]
    },
    %{
      "word" => "run",
      "lang_code" => "en",
      "pos" => "adj",
      "senses" => [%{"glosses" => ["Melted."], "examples" => [%{"text" => "Run *butter*.", "type" => "example"}]}]
    },
    %{
      "word" => "ran",
      "lang_code" => "en",
      "pos" => "verb",
      "senses" => [%{"glosses" => ["simple past of run"], "form_of" => [%{"word" => "run"}]}]
    },
    %{
      "word" => "wonderful",
      "lang_code" => "en",
      "pos" => "adj",
      "senses" => [
        %{
          "glosses" => ["Tending to excite wonder."],
          "translations" => [%{"code" => "pt", "word" => "maravilhoso", "sense" => "excellent"}]
        }
      ]
    }
  ]

  def dictionary_fixture do
    {count, _} = Leitor.Repo.insert_all(Leitor.Dictionary.Entry, Enum.flat_map(@entries, &Import.entry/1))
    count
  end
end
