defmodule Leitor.LanguageStub do
  @moduledoc false
  alias Leitor.Library.Reading

  def generate(_model, prompt, _schema) do
    cond do
      String.contains?(prompt, "Suggest one fresh writing title") ->
        {:ok, %{"title" => "A place I would love to visit"}}

      String.contains?(prompt, "unavailable") ->
        {:error, :unavailable}

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
