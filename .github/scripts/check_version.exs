Mix.start()
Code.compile_file("mix.exs")
version = Leitor.MixProject.project() |> Keyword.fetch!(:version)
Version.parse!(version)

if System.get_env("GITHUB_REF_TYPE") == "tag" do
  tag = System.fetch_env!("GITHUB_REF_NAME")

  unless tag == "v#{version}" do
    IO.puts(:stderr, "A tag #{tag} deve corresponder à versão v#{version} de mix.exs")
    System.halt(1)
  end
end

IO.puts("Versão válida: #{version}")
