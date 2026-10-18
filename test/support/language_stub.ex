defmodule Leitor.LanguageStub do
  @moduledoc false
  alias Leitor.Library.Reading

  def stream(_model, _prompt, on_delta, _options \\ []) do
    text = "## A fresh page\n\nA quiet moment to read."
    on_delta.(text)
    {:ok, %{"markdown" => text}}
  end

  def stream_object(model, prompt, schema, on_fragment, options \\ [])

  def stream_object(_model, %ReqLLM.Context{}, _schema, on_fragment, _options) do
    card = %{
      "meaning" => "maravilhoso",
      "headword" => "wonderful",
      "part_of_speech" => "adjetivo",
      "ipa" => "ˈwʌndərfəl",
      "explanation" => "Aqui descreve uma frase muito boa.",
      "usage_note" => "",
      "forms" => [],
      "examples" => [%{"en" => "What a wonderful day.", "pt" => "Que dia maravilhoso."}],
      "other_senses" => []
    }

    on_fragment.(Jason.encode!(card))
    {:ok, card}
  end

  def stream_object(model, prompt, schema, on_fragment, _options) do
    case generate(model, prompt, schema) do
      {:ok, data} = result ->
        on_fragment.(Jason.encode!(data))
        result

      error ->
        error
    end
  end

  def generate(model, prompt, schema, options \\ [])

  def generate(_model, _prompt, %{properties: %{figure: _}}, _options), do: {:ok, Leitor.FigureFixtures.figure_response()}

  def generate(_model, prompt, _schema, _options) do
    cond do
      String.contains?(prompt, "Suggest one fresh writing title") ->
        {:ok, %{"title" => "A place I would love to visit"}}

      String.contains?(prompt, "unavailable") ->
        {:error, :unavailable}

      String.contains?(prompt, "Help an English learner with the selected passage") ->
        {:ok, %{"answer" => "Very good or pleasing.", "meaning" => "maravilhoso", "category" => "adj"}}

      String.contains?(prompt, "Answer a reading question") ->
        {:ok, %{"answer" => "Yesterday calls for the simple past.", "references" => [1]}}

      String.contains?(prompt, "language question") ->
        {:ok, %{"answer" => "Yesterday calls for the simple past."}}

      String.contains?(prompt, "Create a study guide") ->
        {:ok,
         %{
           "grammar" => %{
             "title" => "Past tense",
             "body" => "Use went for the past of go.",
             "pattern" => "subject + past"
           },
           "vocabulary" => [%{"term" => "went", "meaning" => "foi", "category" => "verb"}]
         }}

      String.contains?(prompt, "Analyze this English") ->
        {:ok,
         %{
           "translation" => "Ela foi à escola ontem.",
           "tense" => "Past simple",
           "focus" => %{"title" => "Past tense", "body" => "Notice went.", "pattern" => "subject + past"},
           "chunks" => [],
           "tokens" =>
             prompt
             |> String.split("Sentence:\n")
             |> List.last()
             |> Reading.prepare()
             |> hd()
             |> Map.fetch!(:tokens)
             |> Enum.map(fn token -> Map.new(token, fn {key, value} -> {Atom.to_string(key), value} end) end)
         }}

      true ->
        {:ok,
         %{
           "summary" => "Use the simple past.",
           "corrected" => "She went to school yesterday.",
           "alternatives" => ["Yesterday, she went to school."],
           "issues" => [
             %{"from" => "go", "to" => "went", "kind" => "grammar", "explanation" => "Yesterday requires the past form."}
           ]
         }}
    end
  end
end
