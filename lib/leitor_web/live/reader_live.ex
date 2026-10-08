defmodule LeitorWeb.ReaderLive do
  @moduledoc false
  use LeitorWeb, :live_view

  alias Leitor.Language
  alias Leitor.Learning
  alias Leitor.Library
  alias Leitor.Library.Import
  alias Leitor.Library.Reading

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(
       mode: :home,
       title: "A Scandal in Bohemia",
       sentences: Reading.sample(),
       index: 0,
       text: nil,
       colors: true,
       structure: false,
       translation: false,
       only_new: false,
       selected: nil,
       phrase_mode: false,
       phrase_start: nil,
       known: MapSet.new(),
       saved: MapSet.new(),
       busy: false,
       answer: nil,
       analysis_cache: %{},
       started_at: System.monotonic_time(:second),
       paste_open: false,
       due_count: 0,
       form: to_form(%{"title" => "", "body" => ""}, as: "reading"),
       question_form: to_form(%{"question" => ""}, as: "ask")
     )
     |> stream(:home_library, [])
     |> allow_upload(:document, accept: ~w(.txt .pdf .epub .docx), max_entries: 1, max_file_size: 10_000_000)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    socket = socket |> reset_analysis() |> assign(analysis_cache: %{})

    socket =
      case socket.assigns.live_action do
        :saved ->
          text = Library.get_text!(socket.assigns.current_scope, params["id"])
          sentences = Reading.prepare(text.body)

          assign(socket,
            mode: :read,
            title: text.title,
            text: text,
            sentences: sentences,
            index: min(text.position, max(length(sentences) - 1, 0))
          )

        :sample ->
          assign(socket, mode: :read, sentences: Reading.sample(), title: "A Scandal in Bohemia", index: 0, text: nil)

        :home ->
          assign(socket, mode: :home)
      end

    socket =
      if socket.assigns.current_scope do
        entries = Learning.list_entries(socket.assigns.current_scope)

        socket
        |> assign(
          known: MapSet.new(for e <- entries, e.status == "known", do: e.term),
          saved: MapSet.new(Enum.map(entries, & &1.term)),
          due_count:
            Enum.count(entries, &(&1.status != "known" && DateTime.compare(&1.due_at, DateTime.utc_now()) != :gt))
        )
        |> stream(:home_library, socket.assigns.current_scope |> Library.list_texts() |> Enum.take(5), reset: true)
      else
        socket
      end

    {:noreply, current(socket)}
  end

  @impl true
  def handle_event("paste", _, socket), do: {:noreply, assign(socket, paste_open: not socket.assigns.paste_open)}

  def handle_event("validate", %{"reading" => params}, socket),
    do: {:noreply, assign(socket, form: to_form(params, as: "reading"))}

  def handle_event("prepare", %{"reading" => params}, socket) do
    body = String.trim(params["body"] || "")

    if body == "" or byte_size(body) > 300_000 do
      {:noreply, put_flash(socket, :error, "Paste a text between 1 and 300,000 bytes.")}
    else
      {:noreply,
       socket
       |> reset_analysis()
       |> assign(
         mode: :read,
         sentences: Reading.prepare(body),
         title: title(params["title"]),
         index: 0,
         text: nil,
         analysis_cache: %{}
       )
       |> current()}
    end
  end

  def handle_event("upload", _, socket) do
    results =
      consume_uploaded_entries(socket, :document, fn %{path: path}, entry ->
        {:ok, {entry.client_name, Import.extract(path, entry.client_name)}}
      end)

    case results do
      [{name, {:ok, body}}] ->
        {:noreply,
         socket
         |> reset_analysis()
         |> assign(
           mode: :read,
           sentences: Reading.prepare(body),
           title: Path.rootname(name),
           index: 0,
           text: nil,
           analysis_cache: %{}
         )
         |> current()}

      [{_, {:error, reason}}] ->
        {:noreply, put_flash(socket, :error, reason)}

      _ ->
        {:noreply, put_flash(socket, :error, "Choose a document first.")}
    end
  end

  def handle_event("validate-upload", _, socket), do: {:noreply, socket}
  def handle_event("cancel-upload", %{"ref" => ref}, socket), do: {:noreply, cancel_upload(socket, :document, ref)}

  def handle_event("toggle", %{"layer" => layer}, socket)
      when layer in ["colors", "structure", "translation", "only_new"] do
    key = %{"colors" => :colors, "structure" => :structure, "translation" => :translation, "only_new" => :only_new}[layer]
    {:noreply, assign(socket, key, not socket.assigns[key])}
  end

  def handle_event("move", %{"direction" => direction}, socket) when direction in ["next", "previous"] do
    index = socket.assigns.index + if(direction == "next", do: 1, else: -1)
    index = max(0, min(index, length(socket.assigns.sentences) - 1))

    socket =
      if index == socket.assigns.index do
        socket
      else
        socket = record_read(socket)

        if socket.assigns.text,
          do: Library.update_text(socket.assigns.current_scope, socket.assigns.text, %{position: index})

        socket
        |> reset_analysis()
        |> assign(index: index, selected: nil, answer: nil, busy: false)
        |> current()
      end

    {:noreply, socket}
  end

  def handle_event("phrase-mode", _, socket),
    do: {:noreply, assign(socket, phrase_mode: !socket.assigns.phrase_mode, phrase_start: nil, selected: nil)}

  def handle_event("select-expression", %{"text" => text}, socket) do
    text = String.trim(text)

    if String.length(text) <= 200 && length(Reading.words(text)) in 2..12 &&
         String.contains?(socket.assigns.sentence.body, text) do
      {:noreply, select_phrase(socket, text)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("select", %{"index" => raw}, socket) do
    case Integer.parse(raw) do
      {index, ""} when index >= 0 ->
        if index < length(socket.assigns.sentence.tokens),
          do: {:noreply, select_token(socket, index)},
          else: {:noreply, socket}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("close", _, socket),
    do: {:noreply, socket |> assign(selected: nil) |> push_event("restore-word-focus", %{})}

  def handle_event("save-text", _, %{assigns: %{current_scope: nil}} = socket), do: login_required(socket)

  def handle_event("save-text", _, socket) do
    attrs = %{
      title: socket.assigns.title,
      body: Enum.map_join(socket.assigns.sentences, "\n\n", & &1.body),
      source: "reading",
      position: socket.assigns.index
    }

    case Library.create_text(socket.assigns.current_scope, attrs) do
      {:ok, text} ->
        {:noreply, socket |> put_flash(:info, "Saved to your library.") |> push_navigate(to: ~p"/read/#{text.id}")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "We couldn't save this text. Try a shorter title or chapter.")}
    end
  end

  def handle_event("save-word", _, %{assigns: %{current_scope: nil}} = socket), do: login_required(socket)

  def handle_event("save-word", %{"status" => status}, socket) when status in ["known", "learning"] do
    save_selected_word(socket, socket.assigns.selected, status)
  end

  def handle_event("practice", _, %{assigns: %{current_scope: nil}} = socket), do: login_required(socket)

  def handle_event("practice", _, socket) do
    attrs = %{
      title: socket.assigns.title,
      body: Enum.map_join(socket.assigns.sentences, "\n\n", & &1.body),
      source: "reading",
      position: socket.assigns.index
    }

    case Library.create_text(socket.assigns.current_scope, attrs) do
      {:ok, text} ->
        {:noreply, push_navigate(socket, to: ~p"/practice?#{%{text: text.id, sentence: socket.assigns.index}}")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Save this reading before starting a practice session.")}
    end
  end

  def handle_event("analyze", _, %{assigns: %{busy: true}} = socket), do: {:noreply, socket}

  def handle_event("analyze", _, socket) do
    body = socket.assigns.sentence.body
    {:noreply, socket |> assign(busy: true) |> start_async(:analysis, fn -> Language.analyze(body) end)}
  end

  def handle_event("ask", %{"ask" => %{"question" => question}}, socket) do
    if socket.assigns.busy or String.trim(question) == "" do
      {:noreply, socket}
    else
      body = socket.assigns.sentence.body

      {:noreply,
       socket
       |> assign(busy: true)
       |> start_async(:question, fn -> Language.explain(body, question) end)}
    end
  end

  @impl true
  def handle_async(:analysis, {:ok, {:ok, data}}, socket) do
    index = socket.assigns.index

    sentence = %{
      body: Enum.at(socket.assigns.sentences, index).body,
      translation: data["translation"],
      tense: data["tense"],
      focus: %{title: data["focus"]["title"], body: data["focus"]["body"], pattern: data["focus"]["pattern"]},
      chunks: Enum.map(data["chunks"], &[&1["text"], &1["role"]]),
      tokens:
        Enum.map(data["tokens"], fn t ->
          %{
            word: t["word"],
            category: t["category"],
            ipa: t["ipa"],
            meaning: t["meaning"],
            definition: t["definition"],
            note: t["note"]
          }
        end)
    }

    cache = Map.put(socket.assigns.analysis_cache, index, sentence)
    {:noreply, socket |> assign(analysis_cache: cache, busy: false) |> current()}
  end

  def handle_async(:question, {:ok, {:ok, data}}, socket) do
    {:noreply, assign(socket, busy: false, answer: data["answer"])}
  end

  def handle_async(_, _, socket),
    do:
      {:noreply,
       socket
       |> assign(busy: false)
       |> put_flash(:error, "The tutor couldn't respond. Your reading is safe; please try again.")}

  defp select_token(%{assigns: %{phrase_mode: false}} = socket, index),
    do: assign(socket, selected: Enum.at(socket.assigns.sentence.tokens, index))

  defp select_token(%{assigns: %{phrase_start: nil}} = socket, index), do: assign(socket, phrase_start: index)

  defp select_token(socket, index) do
    first = min(socket.assigns.phrase_start, index)
    last = max(socket.assigns.phrase_start, index)
    phrase = socket.assigns.sentence.tokens |> Enum.slice(first..last) |> Enum.map_join(" ", & &1.word)

    if String.length(phrase) <= 200 && last - first < 12,
      do: select_phrase(socket, phrase),
      else: assign(socket, phrase_start: nil)
  end

  defp select_phrase(socket, phrase) do
    assign(socket,
      selected: %{word: phrase, category: "expression", meaning: "", definition: "", note: "", ipa: ""},
      phrase_mode: false,
      phrase_start: nil
    )
  end

  defp save_selected_word(socket, nil, _status), do: {:noreply, socket}

  defp save_selected_word(socket, word, status) do
    attrs = %{
      term: word.word,
      meaning: if(word.meaning == "", do: "Add your own meaning", else: word.meaning),
      category: word.category,
      context: socket.assigns.sentence.body,
      status: status
    }

    case Learning.save_word(socket.assigns.current_scope, attrs) do
      {:ok, entry} ->
        {:ok, _} = Learning.update_entry(socket.assigns.current_scope, entry, %{status: status})

        known =
          if status == "known",
            do: MapSet.put(socket.assigns.known, entry.term),
            else: MapSet.delete(socket.assigns.known, entry.term)

        {:noreply,
         socket
         |> assign(known: known, saved: MapSet.put(socket.assigns.saved, entry.term))
         |> put_flash(
           :info,
           if(status == "known", do: "Marked as known in all your texts.", else: "Saved to your words.")
         )}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Couldn't save that word. Try again.")}
    end
  end

  defp reset_analysis(socket),
    do:
      socket
      |> cancel_async(:analysis)
      |> cancel_async(:question)
      |> assign(busy: false, answer: nil, selected: nil, phrase_start: nil, phrase_mode: false)

  defp current(socket) do
    sentence =
      Map.get(socket.assigns.analysis_cache, socket.assigns.index) ||
        Enum.at(socket.assigns.sentences, socket.assigns.index) || hd(Reading.sample())

    assign(socket,
      sentence: sentence,
      page_title: if(socket.assigns.mode == :home, do: "Read", else: socket.assigns.title)
    )
  end

  defp title(nil), do: "Untitled reading"
  defp title(text), do: if(String.trim(text) == "", do: "Untitled reading", else: String.slice(String.trim(text), 0, 180))

  defp login_required(socket),
    do:
      {:noreply,
       socket |> put_flash(:info, "Log in with email to save your progress.") |> push_navigate(to: ~p"/users/log-in")}

  defp record_read(socket) do
    if socket.assigns.current_scope do
      elapsed = min(max(System.monotonic_time(:second) - socket.assigns.started_at, 0), 1800)

      Learning.create_attempt(socket.assigns.current_scope, %{
        kind: "read",
        content: socket.assigns.sentence.body,
        result: %{},
        duration: elapsed
      })
    end

    assign(socket, started_at: System.monotonic_time(:second))
  end
end
