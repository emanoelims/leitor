defmodule Leitor.Figures.Runner do
  @moduledoc "Runs authored browser programs in a disposable, networkless container. There is deliberately no host execution fallback."
  alias Leitor.Figures.RemoteRunner

  @doc "Compiles and browser-tests source in a bounded container, returning evidence and images or a recoverable runner error."
  @spec check(map()) :: {:ok, map()} | {:error, :runner_unavailable | :runner_timeout | :invalid_response}
  def check(program) do
    config = Application.get_env(:leitor, :figure_runner, [])

    cond do
      not Keyword.get(config, :enabled, false) -> {:error, :runner_unavailable}
      Keyword.get(config, :url) -> RemoteRunner.check(program, config)
      System.find_executable("docker") -> run(program, config)
      true -> {:error, :runner_unavailable}
    end
  end

  defp run(program, config) do
    id = "leitor-figure-" <> Ecto.UUID.generate()
    directory = Path.join(Path.expand(Keyword.get(config, :workspace, "tmp/figure-runs")), id)
    input = Path.join(directory, "input")
    output = Path.join(directory, "output")
    File.mkdir_p!(input)
    File.mkdir_p!(output)
    File.chmod!(directory, 0o700)
    File.chmod!(output, 0o777)

    try do
      for name <- ~w(figure.mjs geometry.mjs model.mjs),
          do: File.write!(Path.join(input, name), Map.fetch!(program, name))

      File.write!(Path.join(input, "checks.mjs"), Map.get(program, "checks.mjs", "export function verify(){return []}"))

      File.write!(
        Path.join(input, "request.json"),
        Jason.encode!(
          Map.take(program, ~w(css experiments capture_steps model_checks_required model_only motion_required))
        )
      )

      image = Keyword.get(config, :image, "leitor-figure-runner:1")
      args = docker_args(id, image, input, output)

      port =
        Port.open({:spawn_executable, System.find_executable("docker")}, [
          :binary,
          :exit_status,
          :stderr_to_stdout,
          args: args
        ])

      deadline = System.monotonic_time(:millisecond) + 100_000

      case await(port, deadline, 0) do
        :ok -> read_result(output)
        error -> error
      end
    after
      System.cmd("docker", ["rm", "-f", id], stderr_to_stdout: true)
      File.rm_rf(directory)
    end
  end

  defp docker_args(id, image, input, output) do
    [
      "run",
      "--rm",
      "--name",
      id,
      "--network",
      "none",
      "--read-only",
      "--cap-drop",
      "ALL",
      "--security-opt",
      "no-new-privileges",
      "--pids-limit",
      "256",
      "--memory",
      "2g",
      "--memory-swap",
      "2g",
      "--cpus",
      "2",
      "--shm-size",
      "128m",
      "--tmpfs",
      "/tmp:rw,noexec,nosuid,size=256m",
      "--mount",
      "type=bind,source=#{input},target=/input,readonly",
      "--mount",
      "type=bind,source=#{output},target=/output",
      image
    ]
  end

  defp await(port, deadline, bytes) do
    remaining = max(0, deadline - System.monotonic_time(:millisecond))

    receive do
      {^port, {:data, data}} when bytes + byte_size(data) < 64_000 -> await(port, deadline, bytes + byte_size(data))
      {^port, {:data, _}} -> {:error, :invalid_response}
      {^port, {:exit_status, 0}} -> :ok
      {^port, {:exit_status, _}} -> {:error, :runner_unavailable}
    after
      remaining ->
        Port.close(port)
        {:error, :runner_timeout}
    end
  end

  defp read_result(output) do
    with {:ok, json} <- bounded_read(output, "report.json", 50_000),
         {:ok, %{"ok" => ok, "images" => images} = report} when is_boolean(ok) and is_list(images) <- Jason.decode(json) do
      shots =
        for name <- images,
            name in ~w(light.png tested.png detail.png interaction.png dark.png mobile.png),
            {:ok, png} <- [bounded_read(output, name, 2_000_000)],
            do: png

      if length(shots) == length(images) and Enum.uniq(images) == images do
        complete_result(output, %{report: report, images: shots})
      else
        {:error, :invalid_response}
      end
    else
      _ -> {:error, :invalid_response}
    end
  end

  defp complete_result(_output, %{report: %{"ok" => true, "model_only" => true}, images: []} = result), do: {:ok, result}

  defp complete_result(output, %{report: %{"ok" => true}, images: [_ | _]} = result) do
    with {:ok, bundle} <- bounded_read(output, "bundle.js", 1_000_000),
         {:ok, style} <- bounded_read(output, "style.css", 100_000) do
      {:ok, Map.merge(result, %{bundle: bundle, style: style})}
    else
      _ -> {:error, :invalid_response}
    end
  end

  defp complete_result(_output, %{report: %{"ok" => false}} = result), do: {:ok, result}
  defp complete_result(_output, _result), do: {:error, :invalid_response}

  defp bounded_read(directory, name, limit) do
    path = Path.join(directory, name)
    with {:ok, %{size: size, type: :regular}} when size <= limit <- File.lstat(path), do: File.read(path)
  end
end
