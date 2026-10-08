# Contribuindo

Use Elixir da série `1.20` e Erlang/OTP da série `29`, configurados em
`mise.toml`. O mise permite atualizações dentro dessas séries; execute
`mise upgrade` para atualizar as instalações locais. Execute `mise install`,
depois `mise run setup`. Para iniciar o Phoenix, use `mise run dev`. Antes de
abrir um PR, execute `mise run precommit` (executa `mix precommit`).

As tarefas do mise usam automaticamente as ferramentas configuradas. Para
comandos avulsos, use `mise exec -- mix <tarefa>`. Consulte a
[documentação do mise](https://mise.jdx.dev/getting-started.html) para instalação
e ativação no shell.

## Branches e revisão

Crie uma branch como `feat/busca`, `fix/leitura` ou `docs/instalacao` e abra um PR
para `main`. Colaboradores precisam de uma aprovação e discussões resolvidas;
novos commits invalidam aprovações. A `main` não permite exclusão nem force push.
Administradores têm exceção à exigência de PR e revisão.

O merge usa squash: o título do PR vira o commit na `main`. Mantenha o título
atualizado e espere os checks `Conventions` e `Elixir checks` passarem.

## Conventional Commits

Use `<tipo>[escopo opcional][!]: <descrição>` nos commits e no título do PR.
Tipos permitidos: `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`,
`build`, `ci`, `chore` e `revert`. O escopo usa letras minúsculas, números,
ponto, hífen, sublinhado ou barra. A descrição pode ser em português.

Exemplos:

- `feat(reader): adicionar busca`
- `fix(reader): preservar posição de leitura`
- `ci: validar os padrões do projeto`
- `feat(api)!: alterar formato de resposta`

Para mudanças incompatíveis, use `!` no título do PR e descreva a migração no
corpo com `BREAKING CHANGE: ...`. Isso preserva a sinalização no squash.

## Versionamento semântico

A fonte da versão é `version` em `mix.exs`, no formato `MAJOR.MINOR.PATCH`.

- `fix`: incremento PATCH (por exemplo, `1.2.0` → `1.2.1`).
- `feat` compatível: incremento MINOR (`1.2.0` → `1.3.0`).
- Mudança incompatível: incremento MAJOR (`1.2.0` → `2.0.0`).
- Outros tipos não exigem release por si só; avalie o impacto público.

Durante `0.x`, o projeto é experimental: nossa política é incrementar MINOR
para funcionalidades e mudanças incompatíveis e PATCH para correções.
A primeira versão com compromisso de estabilidade será `1.0.0`.

Para uma release, abra um PR `chore(release): preparar X.Y.Z`, atualize
`mix.exs` e registre mudanças e migrações em `CHANGELOG.md`. Após o merge e CI
verde na `main`, crie a tag `vX.Y.Z` no commit correspondente. O CI confere se
a tag corresponde exatamente ao `mix.exs`. Pré-releases podem usar
`X.Y.Z-rc.1`. O incremento é revisado manualmente; não há publicação automática.

## Elixir e Phoenix

Siga `AGENTS.md`, o formatador configurado em `.formatter.exs` e as convenções
oficiais: módulos em `CamelCase`, funções e variáveis em `snake_case`, predicados
com `?`, funções que levantam exceções com `!` quando houver essa convenção de API.
Use contextos Phoenix para lógica de negócio e preserve a separação da camada web.
O CI exige formatação, compilação sem warnings, ausência de dependências não
utilizadas no lockfile e testes passando. Não adicionamos ferramentas ou
dependências de análise sem uma necessidade concreta.

Referências:

- [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/)
- [SemVer 2.0](https://semver.org/)
- [Version do Elixir](https://hexdocs.pm/elixir/Version.html)
- [Convenções de nomes do Elixir](https://hexdocs.pm/elixir/naming-conventions.html)
- [Diretrizes para bibliotecas Elixir](https://hexdocs.pm/elixir/library-guidelines.html)

As diretrizes para bibliotecas servem como referência; este projeto é uma
aplicação Phoenix e não um pacote publicado no Hex.
