defmodule Leitor.Library.Epub.Package do
  @moduledoc """
  Reads the structure of an EPUB archive: the zip entries, the OPF package, its manifest and its reading order.

  Everything is read in memory and entry names are normalised under `/`, so archive entries can never address
  files outside the package.
  """

  @max_size 10_000_000
  @max_entries 5_000
  @entry ~r/\.(xhtml|html|htm|opf|ncx)$|^META-INF\/container\.xml$/i
  @document_types ~w(application/xhtml+xml text/html)

  @typedoc "Archive text entries keyed by their absolute, normalised path."
  @type files() :: %{String.t() => binary()}
  @typedoc "A manifest item with its path resolved against the package directory."
  @type item() :: %{
          id: String.t() | nil,
          path: String.t(),
          media_type: String.t() | nil,
          properties: [String.t()]
        }
  @typedoc "The parsed OPF package."
  @type t() :: %{
          path: String.t(),
          xml: String.t(),
          manifest: %{String.t() => item()},
          spine: [item()],
          toc: String.t() | nil
        }

  @doc "Reads the text entries (documents, package files and NCX) of an archive without writing to disk."
  @spec read(Path.t()) :: {:ok, files()} | {:error, :invalid_archive}
  def read(path) do
    with {:ok, table} <- :zip.table(String.to_charlist(path)),
         files = Enum.filter(table, &(is_tuple(&1) and elem(&1, 0) == :zip_file)),
         true <- length(files) <= @max_entries,
         true <- Enum.sum(Enum.map(files, &elem(elem(&1, 2), 1))) <= @max_size,
         names = files |> Enum.map(&elem(&1, 1)) |> Enum.filter(&Regex.match?(@entry, List.to_string(&1))),
         {:ok, entries} <- :zip.extract(String.to_charlist(path), [:memory, {:file_list, names}]),
         true <- Enum.all?(entries, fn {_name, data} -> String.valid?(data) end) do
      {:ok, Map.new(entries, fn {name, data} -> {Path.expand(List.to_string(name), "/"), data} end)}
    else
      _ -> {:error, :invalid_archive}
    end
  end

  @doc "Locates and parses the OPF package named by `META-INF/container.xml`."
  @spec parse(files()) :: {:ok, t()} | {:error, :invalid_package | :invalid_spine}
  def parse(files) do
    with container when is_binary(container) <- files["/META-INF/container.xml"],
         [root] <- Regex.run(~r/<(?:[\w-]+:)?rootfile\b[^>]*>/i, container),
         package_path when is_binary(package_path) <- attribute(root, "full-path"),
         package_path = Path.expand(package_path, "/"),
         package when is_binary(package) <- files[package_path],
         [_, spine_tag, spine] <-
           Regex.run(~r/(<(?:[\w-]+:)?spine\b[^>]*>)(.*?)<\/(?:[\w-]+:)?spine>/is, package) do
      manifest = manifest(package, Path.dirname(package_path))

      case spine_items(spine, manifest) do
        {:ok, items} ->
          {:ok, %{path: package_path, xml: package, manifest: manifest, spine: items, toc: attribute(spine_tag, "toc")}}

        :error ->
          {:error, :invalid_spine}
      end
    else
      _ -> {:error, :invalid_package}
    end
  end

  @doc """
  Pairs each readable spine document with its source, skipping non-document items such as SVG covers.
  A document item whose file is missing from the archive invalidates the book.
  """
  @spec documents(files(), t()) :: {:ok, [{item(), String.t()}]} | {:error, :invalid_spine}
  def documents(files, %{spine: spine}) do
    documents = Enum.filter(spine, &document?/1)
    pairs = Enum.map(documents, &{&1, files[&1.path]})

    if pairs != [] and Enum.all?(pairs, &is_binary(elem(&1, 1))), do: {:ok, pairs}, else: {:error, :invalid_spine}
  end

  @doc "Reads one attribute from a single start tag, decoding the XML entities used in attribute values."
  @spec attribute(String.t(), String.t()) :: String.t() | nil
  def attribute(tag, name) do
    case Regex.run(Regex.compile!("\\b" <> name <> "\\s*=\\s*[\"']([^\"']*)[\"']", "i"), tag) do
      [_, value] -> value |> String.replace("&amp;", "&") |> String.replace("&quot;", "\"")
      nil -> nil
    end
  end

  defp document?(%{media_type: type, path: path}),
    do: type in @document_types or (is_nil(type) and Regex.match?(~r/\.(xhtml|html|htm)$/i, path))

  defp manifest(package, directory) do
    ~r/<(?:[\w-]+:)?item\b[^>]*>/i
    |> Regex.scan(package)
    |> Enum.flat_map(fn [tag] -> item(tag, directory) end)
    |> Map.new(&{&1.id, &1})
  end

  defp item(tag, directory) do
    with id when is_binary(id) <- attribute(tag, "id"),
         href when is_binary(href) <- attribute(tag, "href") do
      [
        %{
          id: id,
          path: href |> String.split("#") |> hd() |> safe_decode() |> Path.expand(directory),
          media_type: attribute(tag, "media-type"),
          properties: tag |> attribute("properties") |> List.wrap() |> Enum.flat_map(&String.split/1)
        }
      ]
    else
      _ -> []
    end
  end

  defp spine_items(spine, manifest) do
    items =
      ~r/<(?:[\w-]+:)?itemref\b[^>]*>/i
      |> Regex.scan(spine)
      |> Enum.reject(fn [tag] -> attribute(tag, "linear") == "no" end)
      |> Enum.map(fn [tag] -> manifest[attribute(tag, "idref")] end)

    if items != [] and Enum.all?(items, & &1), do: {:ok, items}, else: :error
  end

  @doc false
  @spec safe_decode(String.t()) :: String.t()
  def safe_decode(value) do
    URI.decode(value)
  rescue
    ArgumentError -> value
  end
end
