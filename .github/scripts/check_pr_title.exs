title = System.fetch_env!("PR_TITLE")

pattern =
  ~r/\A(?:feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert)(?:\([a-z0-9][a-z0-9._\/-]*\))?!?: \S[^\r\n]*\z/u

unless Regex.match?(pattern, title) do
  IO.puts(
    :stderr,
    "Título inválido. Use Conventional Commits, por exemplo: feat(reader): adicionar busca"
  )

  System.halt(1)
end
