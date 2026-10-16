defmodule Leitor.Library.Import do
  @moduledoc "Extracts bounded text from uploaded Markdown, TXT, EPUB, DOCX, text-based PDF documents, and photos through local OCR."

  @typedoc "Imported text and a detected title, falling back to Untitled."
  @type document() :: %{title: String.t(), body: String.t()}

  @max_size 10_000_000
  @doc "Extracts a document without writing archive entries to disk; returns an explicit extraction error."
  @spec extract(Path.t(), String.t()) :: {:ok, String.t()} | {:error, String.t()}
  def extract(path, name) do
    result =
      case String.downcase(Path.extname(name)) do
        extension when extension in [".txt", ".md", ".markdown"] -> File.read(path)
        ".pdf" -> pdf(path)
        extension when extension in [".png", ".jpg", ".jpeg"] -> photo(path)
        ".epub" -> archive(path, :epub)
        ".docx" -> archive(path, :docx)
        _ -> {:error, "Choose a Markdown, TXT, EPUB, DOCX, PDF, JPG, or PNG file."}
      end

    validate_text(result)
  end

  @doc """
  Extracts a bounded document and derives its title without using its filename.

  EPUB/DOCX title metadata and PDF metadata (when `pdfinfo` is installed) take
  precedence over a Markdown heading or an isolated first-line title. Missing or
  unreadable optional metadata falls back to the content, then `Untitled`.
  Text extraction errors are returned unchanged; the body is preserved.
  """
  @spec extract_document(Path.t(), String.t()) :: {:ok, document()} | {:error, String.t()}
  def extract_document(path, name) do
    with {:ok, body} <- extract(path, name) do
      detected = metadata_title(path, String.downcase(Path.extname(name)))
      {:ok, %{title: detected || title(body), body: body}}
    end
  end

  @doc ~S"""
  Detects a title from the first top-level Markdown heading or an isolated opening line.

  Inline Markdown is flattened, headings in code or quotes are ignored, and
  titles are limited to 180 characters. Ordinary prose has the title `Untitled`.

  ## Examples

      iex> Leitor.Library.Import.title("# A **quiet** discovery\n\nA passage.")
      "A quiet discovery"

      iex> Leitor.Library.Import.title("A quiet discovery\n\nA passage follows.")
      "A quiet discovery"

      iex> Leitor.Library.Import.title("An ordinary paragraph.")
      "Untitled"
  """
  @spec title(String.t()) :: String.t()
  def title(body) do
    body = body |> String.trim_leading("\uFEFF") |> String.trim()
    document = MDEx.parse_document!(String.slice(body, 0, 300_000))
    heading = Enum.find(document.nodes, &match?(%MDEx.Heading{}, &1))
    detected = if heading, do: normalize_title(inline_text(heading)), else: opening_title(body, document.nodes)
    detected || "Untitled"
  end

  defp opening_title(body, [%MDEx.Paragraph{} = first | _]) do
    case Regex.split(~r/\r?\n[ \t]*\r?\n/, body, parts: 2) do
      [line, rest] ->
        if String.trim(rest) != "" and String.length(line) <= 180 and
             not String.contains?(line, "\n") and not Regex.match?(~r/[.!?;:]$/u, line),
           do: normalize_title(inline_text(first))

      _ ->
        nil
    end
  end

  defp opening_title(_body, _nodes), do: nil

  defp inline_text(%MDEx.Image{}), do: ""
  defp inline_text(%{literal: text}), do: text
  defp inline_text(%{nodes: nodes}), do: Enum.map_join(nodes, &inline_text/1)
  defp inline_text(_), do: " "

  defp normalize_title(text) do
    normalized = text |> String.replace(~r/\s+/u, " ") |> String.trim() |> String.slice(0, 180)
    if normalized != "", do: normalized
  end

  defp metadata_title(path, extension) when extension in [".docx", ".epub"] do
    format = if extension == ".docx", do: :docx_metadata, else: :epub_metadata

    with {:ok, entries} <- archive_contents(path, format),
         xml when is_binary(xml) <- metadata_xml(entries, format),
         [_, text] <- Regex.run(~r/<dc:title\b[^>]*>(.*?)<\/dc:title>/is, xml) do
      text = text |> String.replace("<![CDATA[", "") |> String.replace("]]>", "")
      text |> MDEx.parse_document!() |> inline_text() |> normalize_title()
    else
      _ -> nil
    end
  end

  defp metadata_title(path, ".pdf") do
    case System.find_executable("pdfinfo") do
      nil -> nil
      command -> pdf_title(command, path)
    end
  end

  defp metadata_title(_path, _extension), do: nil

  defp pdf_title(command, path) do
    case System.cmd(command, [path], stderr_to_stdout: true) do
      {info, 0} -> parse_pdf_title(info)
      _ -> nil
    end
  end

  defp parse_pdf_title(info) do
    case Regex.run(~r/^Title:[ \t]*([^\r\n]+)$/m, info) do
      [_, title] -> if String.valid?(title), do: normalize_title(title)
      nil -> nil
    end
  end

  defp metadata_xml(entries, :docx_metadata), do: entries |> Map.new() |> Map.get(~c"docProps/core.xml")

  defp metadata_xml(entries, :epub_metadata) do
    files = Map.new(entries, fn {name, data} -> {Path.expand(List.to_string(name), "/"), data} end)

    with container when is_binary(container) <- files["/META-INF/container.xml"],
         [root] <- Regex.run(~r/<(?:[\w-]+:)?rootfile\b[^>]*>/i, container),
         path when is_binary(path) <- attribute(root, "full-path") do
      files[Path.expand(path, "/")]
    else
      _ -> nil
    end
  end

  defp metadata_entry?(name, :docx_metadata), do: name == ~c"docProps/core.xml"

  defp metadata_entry?(name, :epub_metadata),
    do: name == ~c"META-INF/container.xml" or String.ends_with?(String.downcase(List.to_string(name)), ".opf")

  defp validate_text({:ok, text}) when is_binary(text) do
    cond do
      not String.valid?(text) -> {:error, "This document is not valid UTF-8 text."}
      byte_size(text) > 300_000 -> {:error, "This text is too long. Import a chapter at a time (up to 300,000 bytes)."}
      String.trim(text) == "" -> {:error, "No readable text found. For scanned pages, paste extracted text instead."}
      true -> {:ok, String.trim(text)}
    end
  end

  defp validate_text({:error, message}) when is_binary(message), do: {:error, message}
  defp validate_text(_), do: {:error, "We couldn't read this document. Try exporting it as TXT or paste its text."}

  defp photo(path) do
    case System.find_executable("tesseract") do
      nil ->
        {:error, "Photo import requires Tesseract on the server. Paste the text instead."}

      command ->
        case System.cmd(command, [Path.basename(path), "stdout", "-l", "eng", "quiet"],
               cd: Path.dirname(path),
               stderr_to_stdout: true
             ) do
          {text, 0} -> {:ok, text}
          _ -> {:error, "We couldn't read this photo. Use a clear JPG or PNG, or paste its text."}
        end
    end
  end

  defp pdf(path) do
    case System.find_executable("pdftotext") do
      nil ->
        {:error, "PDF extraction requires pdftotext on the server. Paste the text instead."}

      command ->
        case System.cmd(command, ["-f", "1", "-l", "200", "-enc", "UTF-8", path, "-"], stderr_to_stdout: true) do
          {text, 0} -> {:ok, text}
          _ -> {:error, :invalid_pdf}
        end
    end
  end

  defp archive(path, format) do
    with {:ok, entries} <- archive_contents(path, format),
         {:ok, entries} <- reading_order(entries, format) do
      text =
        Enum.map_join(entries, "\n\n", fn {_name, data} ->
          data
          |> String.replace(~r{</(?:p|div|h[1-6]|w:p)>}i, "\n\n")
          |> String.replace(~r/<[^>]+>/, " ")
          |> String.replace("&amp;", "&")
          |> String.replace("&lt;", "<")
          |> String.replace("&gt;", ">")
          |> String.replace("&nbsp;", " ")
        end)

      {:ok, text}
    else
      _ -> {:error, :invalid_archive}
    end
  end

  defp archive_contents(path, format) do
    with {:ok, table} <- :zip.table(String.to_charlist(path)),
         files = Enum.filter(table, &(is_tuple(&1) and elem(&1, 0) == :zip_file)),
         true <- Enum.sum(Enum.map(files, &elem(elem(&1, 2), 1))) <= @max_size,
         names = files |> Enum.map(&elem(&1, 1)) |> Enum.filter(&archive_entry?(&1, format)),
         {:ok, entries} <- :zip.extract(String.to_charlist(path), [:memory, {:file_list, names}]),
         true <- Enum.all?(entries, fn {_name, data} -> String.valid?(data) end) do
      {:ok, entries}
    else
      _ -> {:error, :invalid_archive}
    end
  end

  defp archive_entry?(name, format) when format in [:docx_metadata, :epub_metadata], do: metadata_entry?(name, format)

  defp archive_entry?(name, :docx), do: List.to_string(name) == "word/document.xml"

  defp archive_entry?(name, :epub),
    do: Regex.match?(~r/\.(xhtml|html|htm|opf)$|^META-INF\/container\.xml$/i, List.to_string(name))

  defp reading_order(entries, :docx), do: {:ok, entries}

  defp reading_order(entries, :epub) do
    files = Map.new(entries, fn {name, data} -> {Path.expand(List.to_string(name), "/"), data} end)

    with container when is_binary(container) <- files["/META-INF/container.xml"],
         [root] <- Regex.run(~r/<(?:[\w-]+:)?rootfile\b[^>]*>/i, container),
         package_path when is_binary(package_path) <- attribute(root, "full-path"),
         package when is_binary(package) <- files[Path.expand(package_path, "/")],
         [_, spine] <- Regex.run(~r/<(?:[\w-]+:)?spine\b[^>]*>(.*?)<\/(?:[\w-]+:)?spine>/is, package) do
      manifest =
        ~r/<(?:[\w-]+:)?item\b[^>]*>/i
        |> Regex.scan(package)
        |> Map.new(fn [item] -> {attribute(item, "id"), attribute(item, "href")} end)

      chapters =
        ~r/<(?:[\w-]+:)?itemref\b[^>]*>/i
        |> Regex.scan(spine)
        |> Enum.reject(fn [item] -> attribute(item, "linear") == "no" end)
        |> Enum.map(&chapter(&1, manifest, package_path, files))

      if chapters != [] and Enum.all?(chapters, & &1), do: {:ok, chapters}, else: {:error, :invalid_spine}
    else
      _ -> {:error, :invalid_package}
    end
  end

  defp chapter([item], manifest, package_path, files) do
    with href when is_binary(href) <- manifest[attribute(item, "idref")],
         path = href |> String.split("#") |> hd() |> URI.decode() |> Path.expand(Path.dirname("/" <> package_path)),
         data when is_binary(data) <- files[path] do
      {path, data}
    end
  end

  defp attribute(tag, name) do
    case Regex.run(Regex.compile!("\\b" <> name <> "\\s*=\\s*[\"']([^\"']*)[\"']", "i"), tag) do
      [_, value] -> value |> String.replace("&amp;", "&") |> String.replace("&quot;", "\"")
      nil -> nil
    end
  end
end
