defmodule Leitor.LanguageTest do
  use ExUnit.Case, async: false

  import Leitor.FigureFixtures

  alias Leitor.Accounts.Preferences
  alias Leitor.Figures.Scene
  alias Leitor.Language
  alias Leitor.Library.Reading

  setup do
    previous = Application.get_env(:leitor, :language_adapter)
    Application.put_env(:leitor, :language_adapter, Leitor.LanguageCapture)

    on_exit(fn ->
      if previous,
        do: Application.put_env(:leitor, :language_adapter, previous),
        else: Application.delete_env(:leitor, :language_adapter)
    end)

    :ok
  end

  test "trusted request credentials and budgets reach both provider paths without entering prompts" do
    {:ok, preferences} =
      Preferences.new(%{
        reading_model: "anthropic:claude-opus-5-5",
        writing_model: "anthropic:claude-opus-5-5"
      })

    options = [model: "anthropic:claude-haiku-5-5", api_key: "request-local-test-key", max_tokens: 2500]
    Process.put(:language_result, {:ok, figure_response()})

    assert {:ok, _} =
             Language.generate_page_text(
               %{prompt: "Explain a workflow", title: "", context: "", format: "visual_explainer"},
               fn _ -> :ok end,
               preferences,
               options
             )

    assert_receive {:language_request, "anthropic:claude-haiku-5-5", writing_prompt, _schema}
    assert_receive {:language_options, passed}
    assert passed[:api_key] == "request-local-test-key"
    assert passed[:max_tokens] == 2500
    refute writing_prompt =~ "request-local-test-key"
    Process.put(:language_result, {:ok, %{"answer" => "A definition.", "meaning" => "sense", "category" => "word"}})

    assert {:ok, _} =
             Language.page_help("define", "word", [%{text: "A word."}], "", [], fn _ -> :ok end, preferences, options)

    assert_receive {:language_request, "anthropic:claude-haiku-5-5", reading_prompt, _}
    assert_receive {:language_options, passed}
    assert passed[:api_key] == "request-local-test-key"
    refute reading_prompt =~ "request-local-test-key"
  end

  test "planned creative formats are rejected before any provider call" do
    for {_label, format} <- Leitor.WritingFormat.planned() do
      assert {:error, :invalid_input} =
               Language.generate_page_text(%{prompt: "A brief", title: "", context: "", format: format})

      refute_receive {:language_request, _, _, _}
    end
  end

  test "account preferences select independent models and AI languages" do
    {:ok, preferences} =
      Preferences.new(%{
        locale: "en",
        ai_locale: "pt_BR",
        reading_model: "anthropic:claude-opus-5-5",
        writing_model: "anthropic:claude-sonnet-5-5"
      })

    Process.put(:language_result, {:ok, %{"answer" => "Uma resposta.", "meaning" => "sentido", "category" => "word"}})
    assert {:ok, _} = Language.page_help("define", "word", [%{text: "A word."}], "", [], nil, preferences)
    assert_receive {:language_request, "anthropic:claude-opus-5-5", prompt, _}
    assert prompt =~ "Brazilian Portuguese"
    assert prompt =~ "replaces"
    Process.put(:language_result, {:ok, figure_response("Uma ideia.")})
    request = %{prompt: "A short passage", title: "", context: ""}
    assert {:ok, _} = Language.generate_page_text(request, fn _ -> :ok end, preferences)
    assert_receive {:language_request, "anthropic:claude-sonnet-5-5", prompt, _schema}
    assert prompt =~ "Preferred response language: Brazilian Portuguese"
    assert prompt =~ "unless the instruction explicitly requests a different language"
    english = %{preferences | ai_locale: "en"}
    assert {:ok, _} = Language.generate_page_text(request, fn _ -> :ok end, english)
    assert_receive {:language_request, _, prompt, _}
    assert prompt =~ "Preferred response language: English"
    assert Language.model(:analysis, %Preferences{}) == Language.model(:analysis)
    assert Language.model(:feedback, %Preferences{}) == Language.model(:feedback)
  end

  test "questions include the selected sentence and nearby source, with a hard context limit" do
    sentences = Reading.prepare(Enum.map_join(1..60, "\n\n", &"Sentence #{&1}: #{String.duplicate("x", 2500)}."))
    Process.put(:language_result, {:ok, %{"answer" => "Grounded in the selected passage.", "references" => [31]}})
    assert {:ok, _} = Language.explain_reading(sentences, 30, "What does this mean?")
    assert_receive {:language_request, _, prompt, schema}
    [_, source] = String.split(prompt, "\nSource:\n", parts: 2)
    assert byte_size(source) <= 24_000
    assert source =~ "[31] Sentence 31"
    assert source =~ "[30] Sentence 30"
    refute source =~ "[1] Sentence 1"
    assert 31 in schema.properties.references.items.enum
  end

  test "answers with invented references, wrong shapes, or empty content are rejected" do
    sentences = Reading.prepare("One sentence.")

    for response <- [
          %{"answer" => "Invented.", "references" => [99]},
          %{"answer" => "", "references" => [1]},
          %{"answer" => "   ", "references" => []},
          %{"answer" => "Missing references"},
          %{"answer" => "Wrong shape", "references" => "1"}
        ] do
      Process.put(:language_result, {:ok, response})
      assert {:error, :invalid_response} = Language.explain_reading(sentences, 0, "Why?")
    end

    Process.put(:language_result, {:error, :unavailable})
    assert {:error, :unavailable} = Language.explain_reading(sentences, 0, "Why?")
  end

  test "page follow-ups include their previous answer and honor an explicit language request" do
    Process.put(:language_result, {:ok, %{"answer" => "**Muito bom.**", "meaning" => "maravilhoso", "category" => "adj"}})
    history = Enum.map(1..12, &%{question: "Question #{&1}", answer: "Answer #{&1}"})

    assert {:ok, _} =
             Language.page_help("ask", "wonderful", [%{text: "A wonderful sentence."}], "em português", history)

    assert_receive {:language_request, _, prompt, _}
    assert prompt =~ "em português"
    assert prompt =~ "Follow the language explicitly requested"
    assert prompt =~ "[¶1] A wonderful sentence."
    assert prompt =~ "using only numbers present in the source"
    assert prompt =~ "Answer 12"
    refute prompt =~ "Answer 1\""
    Process.put(:language_result, {:ok, %{"answer" => "", "meaning" => "", "category" => "word"}})
    assert {:error, :invalid_response} = Language.page_help("ask", "wonderful", [], "Why?")
  end

  test "page generation bounds context, uses the writing model, and validates Markdown" do
    request = %{
      prompt: "Um conto em português",
      title: String.duplicate("T", 200),
      context: String.duplicate("x", 25_000)
    }

    Process.put(:language_result, {:ok, figure_response("Uma oficina.")})
    assert {:ok, %{"markdown" => markdown}} = Language.generate_page_text(request)
    assert markdown =~ "Uma oficina."
    assert markdown =~ "leitor-figure"
    assert_receive {:language_request, model, prompt, schema}
    assert model == Language.model(:feedback)
    assert prompt =~ "Um conto em português"
    assert prompt =~ String.duplicate("x", 24_000)
    refute prompt =~ String.duplicate("x", 24_001)
    refute prompt =~ String.duplicate("T", 181)
    assert schema.properties.figure == Scene.schema()

    for response <- [%{}, %{"markdown" => " "}, %{"markdown" => 12}, %{"markdown" => String.duplicate("x", 12_001)}] do
      Process.put(:language_result, {:ok, response})
      assert {:error, :invalid_response} = Language.generate_page_text(request)
      assert_receive {:language_request, _, _, _}
    end

    Process.put(:language_result, {:error, :unavailable})
    assert {:error, :unavailable} = Language.generate_page_text(request)
    assert_receive {:language_request, _, _, _}

    for invalid <- [" ", String.duplicate("x", 2001)] do
      assert {:error, :invalid_input} = Language.generate_page_text(%{request | prompt: invalid})
      refute_receive {:language_request, _, _, _}
    end
  end

  test "a complete validated figure is emitted atomically, with its selected model and language" do
    Process.put(:language_result, {:ok, figure_response()})
    owner = self()
    request = %{prompt: "Explain queues", title: "", context: ""}
    assert {:ok, %{"markdown" => markdown}} = Language.generate_page_text(request, &send(owner, {:delta, &1}))
    assert_receive {:delta, ^markdown}
    assert_receive {:language_request, _, prompt, _schema}
    assert prompt =~ "Explain queues"
    assert prompt =~ "Anatomy"
    assert {:error, :invalid_input} = Language.generate_page_text(Map.put(request, :format, "unsupported"))
    refute_receive {:language_request, _, _, _}
  end

  test "reading streams retain structured meaning and category validation" do
    Process.put(:language_fragments, [~S({"answer":"A partial), ~S( answer","meaning":"ideia","category":"noun"})])
    Process.put(:language_result, {:ok, %{"answer" => "A partial answer", "meaning" => "ideia", "category" => "noun"}})
    owner = self()
    callback = &send(owner, {:object_fragment, &1})

    assert {:ok, %{"meaning" => "ideia", "category" => "noun"}} =
             Language.page_help("define", "idea", [], "", [], callback)

    assert_receive {:object_fragment, _}
    assert_receive {:object_fragment, _}
    assert_receive {:language_request, _, _, schema}
    assert schema.properties.category.enum != []

    Process.put(
      :language_result,
      {:ok, %{"answer" => "A partial answer", "meaning" => "ideia", "category" => "invented"}}
    )

    assert {:error, :invalid_response} = Language.page_help("define", "idea", [], "", [], callback)
  end
end
