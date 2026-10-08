# Leitor

Install [mise](https://mise.jdx.dev/getting-started.html) and make PostgreSQL
available on `localhost:5432` with the development credentials configured in
`config/dev.exs`. Use your preferred PostgreSQL setup.

From the project directory, install the tools and start Phoenix:

```sh
mise install
mise run setup
mise run dev
```

Visit [`localhost:8080`](http://localhost:8080), or the port configured in
`mise.local.toml`. Mise uses Elixir `1.20.4-otp-29` and Erlang/OTP `29`.

Run `mise run precommit` before submitting changes. It checks compilation,
dependencies, formatting with Styler and the HEEx formatter, strict Credo analysis,
Doctor, documentation generation, Dialyzer, and tests (including doctests).
The first Dialyzer run builds a cache and can take several minutes.

Generate developer documentation with `mise exec -- mix docs --warnings-as-errors`
and open `doc/index.html`. Run `mise exec -- mix test --cover --warnings-as-errors`
for the line coverage report in `cover/`.

## Authentication

Open `/users/log-in` and enter your email. The same magic-link flow creates a
new account or signs in an existing one. Open `/dev/mailbox` for development
emails. Password login and password settings are not exposed. Email changes
require a recent login. Public deployment also requires a production Swoosh
adapter and a verified sender; the development mailbox does not deliver email.

## Reading and learning

`/` and `/read` support anonymous reading, pasted text, and document imports.
Anonymous content stays in the current LiveView; sign in before saving it.
Accounts unlock a private library, word and expression jars, spaced review,
writing feedback, dictation, shadowing, rewriting, lesson materials, and progress.
Progress comes from saved activity rather than demonstration numbers.

Import TXT, EPUB, DOCX, text-based PDF, or clear JPG/PNG photos (up to 10 MB).
PDF extraction requires `pdftotext`; photo OCR requires Tesseract with English
language data. On macOS, `brew install poppler tesseract` supplies both. Missing
tools or unreadable files produce a recoverable import error. Import chapters
separately: extracted text is limited to 300,000 bytes and PDF import to 200 pages.

In the reader, use Left/Right arrows to move between sentences. Tab and Enter
operate word buttons and controls; Escape dismisses dialogs. Select an expression
with the mouse or enable expression selection and choose its first and last word
with the keyboard. Browser speech supplies pronunciation. Shadowing uses microphone
permission and local audio playback; audio is never uploaded or stored. It records
practice time, without claiming automatic pronunciation scoring.

Create a private room at `/rooms` and share its invitation with signed-in readers.
The host controls the shared sentence; Phoenix Presence tracks participants.
Chat is temporary, limited to 50 displayed messages, and does not expose email
addresses. Closing a room revokes its invitation.

Reusable function components are demonstrated at `/dev/componentes` in development.
The warm palette, typography, contextual header, jars, and activity layouts follow
the approved prototypes. Google Fonts are loaded through stylesheet links.

## Language tutor

ReqLLM sends text to Anthropic only when a learner requests analysis, feedback,
a lesson guide, or an explanation. Set credentials in the environment or the
ignored `mise.local.toml`; never commit them:

```toml
[env]
ANTHROPIC_API_KEY = "your-personal-key"
LEITOR_ANALYSIS_MODEL = "anthropic:claude-haiku-5-5"
LEITOR_FEEDBACK_MODEL = "anthropic:claude-sonnet-5-5"
```

These model settings are also the defaults. Analysis favors the lighter model;
writing feedback uses Sonnet. Override either setting to evaluate another
Anthropic model. Restart the development server after changing its environment.
Provider failures preserve the learner's text and allow retrying. Structured
responses are schema validated, and sentence analysis must preserve the original
words and punctuation. AI suggestions still require the learner's judgment.
Lesson guides analyze the first 12,000 characters and remain saved with the lesson.

## Persistence

`Library`, `Learning`, and `Study` follow generated Phoenix context boundaries and
receive `Accounts.Scope` first. Ownership is enforced in queries and mutations;
room guests receive only invitation-authorized collaboration operations. New
application records use Ecto's native UUID v7 generation. Migrations preserve
existing account identities. Run `mise exec -- mix ecto.migrate` after updating.

Ready to run in production? Please [check our deployment guides](https://phoenix.hexdocs.pm/deployment.html).

## Learn more

* Official website: https://www.phoenixframework.org/
* Guides: https://phoenix.hexdocs.pm/overview.html
* Docs: https://phoenix.hexdocs.pm
* Forum: https://elixirforum.com/c/phoenix-forum
* Source: https://github.com/phoenixframework/phoenix

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for PR rules, Conventional Commits,
semantic versioning, domain typespecs, documentation and doctest patterns, and
Elixir/Phoenix checks. The [authentication contracts](guides/authentication-contracts.md)
connect current behavior to its test evidence and document its limits.

Report vulnerabilities privately as described in [SECURITY.md](SECURITY.md).

## Optional Tidewave MCP

Tidewave is available inside the Phoenix development server only in development.
Each contributor configures their own MCP client; the repository does not ship
an MCP registration or modify global client settings.

Start Phoenix with `mise run dev`. The default endpoint is
`http://localhost:8080/tidewave/mcp`. To connect Codex globally, optionally run:

```sh
codex mcp add tidewave --url http://localhost:8080/tidewave/mcp
```

To use another port, set `PORT` in the ignored `mise.local.toml` and configure
your MCP client with the same port:

```toml
[env]
PORT = "8081"
```

Check the effective port with `mise exec -- printenv PORT`. A local `PORT`
entry overrides an exported value; remove the entry to use `export PORT=...`
instead. Restart Phoenix after changing its port and update your personal MCP
registration separately. A running desktop client does not automatically inherit
the mise environment or update a saved URL.

`AGENTS.md` describes how to use Tidewave when connected. Runtime tools use the
development app and database and complement the test and quality checks.

See the [Tidewave MCP guide](https://tidewave.hexdocs.pm/mcp.md) for connection
troubleshooting and the optional proxy for worktrees running on different ports.

### Floating panels

Reader tools, the color guide and the account menu use `@floating-ui/dom`,
bundled through esbuild. `mix assets.setup` installs the locked npm dependencies;
Node.js 22 is managed by mise. After pulling dependency changes, run
`mise exec -- mix assets.setup`.

The `Floating` hook adapts the positioning lifecycle from
[Sisteo](https://github.com/emanoelims/sisteo/blob/main/lib/sisteo_web/components/core_components.ex).
Attach it to an empty, ignored controller inside a native `details` element,
with a unique ID, `data-panel` pointing to the panel ID and `data-placement`
such as `bottom-end` or `top-start`. The panel needs `floating-panel`.
LiveView retains ownership of panel content; the hook only positions it.
Automatic updates run while open and are cleaned up on close or destruction,
following [Floating UI's lifecycle guidance](https://floating-ui.com/docs/autoUpdate).
Native disclosure keyboard behavior and Phoenix JS handle opening, Escape
and outside clicks.

### Paragraph writing

Writing uses an inline Tiptap editor with Markdown persistence and an MDEx-rendered
preview. Type `/` at the start of a paragraph to insert text, headings, lists,
checklists, quotes, code blocks, or dividers. Filter by typing, choose with ↑/↓ and
Enter, and dismiss with Escape. Markdown shortcuts such as `## `, `- `, `> `,
`**bold**`, and `*italic*` render as you type. Pasted Markdown supports the same
blocks. Cmd/Ctrl+Z undoes changes; Cmd/Ctrl+S saves the draft.

The cursor selects the prose paragraph sent to the tutor, including headings and
list items. Code blocks and dividers are excluded. Applying a suggestion replaces
only that paragraph; changed paragraphs must be reviewed again. The eye button
opens the server-rendered preview. Saved drafts and feedback remain available in
the header's history menu. Existing plain-text drafts retain their literal text;
new edits save as Markdown. Reading and writing share the same document measure
and `StudyComponents.reading_toolbar/1` function component.

User drafts are untrusted Markdown: MDEx sanitizes HTML, escapes raw tags, and
never compiles HEEx or evaluates Phoenix components. MDEx's HEEx/component support
is reserved for trusted application templates. This editor supports the blocks
listed above, not every MDEx extension (for example, tables and embedded components).

Run browser regression tests against a development server using
`npm --prefix assets run test:browser` (install Chromium once with
`cd assets && npx playwright install chromium`). Set `BASE_URL` for another port.
Tests create isolated accounts through the development mailbox; no external email
is sent. Screenshots and browser artifacts are written to the ignored `tmp/` folder.
