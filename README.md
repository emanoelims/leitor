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

All product pages require login, including `/`, `/pages`, `/notebook`, and word jars.
Registration and authentication follow Phoenix 1.8's generated flow: register an
email, then sign in through a single-use magic link. Browser password login and
password updates are unavailable, including for existing accounts that retain a
legacy password hash. Account email changes require a recent email-link login.
Open `/dev/mailbox` for development emails.
Public deployment requires a production Swoosh adapter and a verified sender;
the development mailbox does not deliver external email.

## Reading and learning

The UI uses application-owned Phoenix function components and Tailwind CSS,
without daisyUI or another component framework. `CoreComponents` provides buttons,
inputs, validation, notices, and anchored popovers. Shared control styles live in
`assets/css/components.css`; palettes and reading interactions are adapted from
the local Gloss reference. All workspace and account screens use these palettes.

Leitor's own open-folio mark replaces Phoenix's logo and browser icon. Its vector
source is `priv/static/images/logo.svg`, rendered through `CoreComponents.icon/1`
and used as the SVG favicon. Registration, email sign-in, and confirmation share
an editorial entry layout with a reading-and-margin preview.

The universal application shell lives in `LeitorWeb.Layouts.app/1`. Its `menu`
slot defaults to a Pages / Notebook context selector, `tabs` follows the context
with a divider, and `tools` supplies contextual controls. The account menu stays
owned by the layout. Creating a page is also available in the context selector.
The shelf’s filled **Add page** button opens a single menu with **Blank page**
and **Import text** actions, using the shared Floating UI popup. Closing the
importer restores focus to the Add page button.

Page source tabs and notebook view tabs live in the header; search, ordering,
annotation filters, and word filters live in its shared Floating UI submenu.
Menus open below the full header when its tabs wrap on mobile. Filters retain
shareable URLs and survive reloads. Reader and editor screens instead show a
close link to `/pages` and the page title on the left, with only contextual
controls and the account menu on the right. Saving stays in that header as a
primary action while editing; the ⌘/Ctrl S shortcut also remains available.
Reading titles follow the same size
preference as the document, including on mobile.

The workspace has a page shelf and a combined notebook. Create any number of private
pages at `/pages/new`, paste a text or Markdown, and save it as a formatted reading.
The page shelf has title search, source filters, recent/title ordering, readable
previews, and estimated reading time. Imports use a single paste-or-upload surface
with no title field. Titles come from document metadata, a Markdown heading
(including setext), or a short isolated opening line; otherwise they are `Untitled`.
A filename is never used as a substitute title. Validation
and extraction errors preserve typed text, and successful imports return to the
unfiltered shelf. Imported texts open in the same page reader. The appearance menu ports Gloss’s complete Look and Text controls: Auto, Paper,
Sepia, Snow, Night and Ink themes; Vermilion, Cobalt, Moss and Graphite pens;
Newsreader, Literata, Schibsted and Atkinson Hyperlegible Next fonts; text sizes
from 15 to 28; line spacing, column width, alignment and spaced or indented paragraphs.
Fonts are served locally, including their licenses. Auto follows the system palette,
and theme changes use Gloss’s circular reveal when motion is allowed.
Reading preferences persist in the browser. Paragraph numbers are hidden by default;
the Numbers switch enables them without hiding citation references. Map can be
hidden independently. Focus hides the margin, map and paragraph addresses, lets the
header recede until hovered or focused, and fades paragraphs already read. F toggles
focus and Escape leaves it; focus is temporary for the current page. Text reset
preserves the palette, pen, Numbers and Map choices. The keyboard help explains
notebook and scroll-map shortcuts.

The notebook at `/notebook` brings together notes and word jars in two sections.
`/notebook?view=words` opens the collected words; `/vocabulary` redirects there.
Word filters and literal searches in terms, meanings, and context are reflected
in the URL. Editing and known status retain the existing ownership rules.
The notes section gathers annotations from every owned page,
with literal search, source-page and annotation-type filters, and pagination of
30 entries per page. Source links open the page and highlight the reanchored
passage when it still exists. The page notebook remains available in the reading
tools and with N, preserving page-specific notes, editing, and export.

The block editor supports headings, lists, checklists, quotes, code and `/` commands.
Read without contacting an AI provider. Double-click a word or select across formatted
blocks to keep a note or collect vocabulary. Definitions
and explanations call Anthropic only on request. The notebook opens as a right-hand
sheet and filters highlights, notes, definitions and questions. Its entries link
back to the source and can be sent to a grammatical word jar with an explicit meaning.
The corner minimap uses Gloss’s paragraph lines, vermilion annotation dots and
viewport outline, with clicking, dragging and keyboard travel. Notes and
highlights persist per account. The selection toolbar's highlighter applies the last chosen color on click.
Hover or keyboard focus reveals yellow, green, blue and rose swatches inline,
using Gloss's width transition; touch devices keep the swatches visible.
The marker sweep and saved highlight share Gloss’s translucent ink, with 46%
opacity on light themes and 24% on dark themes, and preserve the surrounding text color.
Click an existing highlight to recolor it or erase it from the toolbar. Highlights
appear in the notebooks and minimap and can also be removed from the notebook.
Unique quotations are reanchored after edits; removed
or ambiguous passages are retained in the notebook without pointing to another text.
The bottom question toolbar is absent from this workspace.

The selection lens, paper palette, marker sweep, underline draw, waiting lines,
and margin-card movement are ported from the local Gloss reference. Active cards
connect to their source; nearby responses collapse into one-line summaries. Cards
appear directly at their first anchor, retain their position through LiveView
patches, and glide when switching notes without replaying the entrance animation.
The reader uses the same Lucide icon geometry as Gloss, bundled locally with its
ISC license in `assets/vendor/lucide`. Ask follow-ups
inside a response (including a request for Portuguese), retry, copy, or stop a
pending answer. Completed exchanges remain owned by the page and persist together,
up to 20 follow-ups per annotation, including notebook Markdown exports.
Definitions, explanations, simplifications, questions, retries and follow-ups use
ReqLLM object streaming. Cards show the provisional answer in small batches while
the full answer, meaning and word category are validated before persistence.
Cancelled, failed or truncated streams preserve previous annotations and replies.
Click empty paper to collapse an open note. Paragraph badges and valid ¶ citations
inside answers preview their source on hover or keyboard focus and jump there on
click, briefly highlighting the destination with Gloss’s fading paragraph wash.
Repeated clicks restart the effect; reduced-motion preferences use a static wash
and immediate navigation. Floating UI keeps previews and selection menus anchored and within the viewport.
Hovering a marked passage or its card draws their connector without opening the
card. An open card keeps its connector while another is previewed. Native text
selection survives card updates, and the selection lens follows Gloss sizing,
theme colors, and contextual word/passage actions.

The product routes are `/` and `/pages` (the page library), `/pages/new`,
`/pages/:id`, and `/notebook`, plus account and
authentication flows. The former sentence reader, writing, lessons, exercises,
review, progress, rooms, resource-management screens, and component gallery
have been removed. Their database records remain intact.

The shelf accepts Markdown (.md/.markdown), TXT, EPUB, DOCX, and text-based PDF files (up to 10 MB).
EPUB and DOCX title metadata are read locally. Optional `pdfinfo` supplies PDF titles.
PDF extraction requires `pdftotext` (`brew install poppler` on macOS). Missing
tools or unreadable files produce a recoverable import error. Import chapters
separately: extracted text is limited to 300,000 bytes and PDF import to 200 pages.

## Language tutor

### Markdown code highlighting

MDEx uses Lumis for fenced code in the reader, annotation answers, and streamed
draft previews. Label fences with a language, for example `elixir`, `js`, `ts`,
`tsx`, `html`, `css`, `json`, `heex`, `python`, or `bash`. Unlabelled fences and
uninstalled languages remain escaped plain code. Code is never executed.

The bundled GitHub light/dark palettes in `assets/css/lumis.css` follow the
reading theme, including Auto, without fetching assets or rerendering content.
Parser packages are release dependencies; add a `lumis_wasm_*` dependency to
support another language. The comment grammar supports Elixir's injections.
Each code block has a cooperative 1-second highlighting budget and a 4096-match
limit; exceeding the time budget falls back to plain code. These limits exclude
parser loading and do not bound total document rendering time.

`config :mdex_native, syntax_highlighter: :lumis` selects the native artifact at
compile time. After changing it in an existing checkout, stop the development
server, run `mise exec -- mix deps.compile mdex_native mdex --force`, then restart
with `mise run dev`.

### Claude configuration

ReqLLM sends text to Anthropic only when a learner requests a definition,
explanation, simplification, or question response. Set credentials in the environment or the
ignored `mise.local.toml`; never commit them:

```toml
[env]
ANTHROPIC_API_KEY = "your-personal-key"
LEITOR_ANALYSIS_MODEL = "anthropic:claude-haiku-5-5"
LEITOR_FEEDBACK_MODEL = "anthropic:claude-sonnet-5-5"
```

These model settings are also the defaults. Page assistance uses the analysis
model. The feedback setting remains available to the retained domain APIs.
Restart the development server after changing its environment.
Provider failures preserve the learner's text and allow retrying. Structured
responses are schema validated, and sentence analysis must preserve the original
words and punctuation. AI suggestions still require the learner's judgment.

### Dictionary

The selection toolbar's Dictionary action answers in a margin card, like Define
and Explain, and keeps its meaning and part of speech for word jars. Claude
receives the surrounding page text (up to about 24,000 characters) and the
paragraph with the selected occurrence marked, so the card explains the meaning
used there: meaning in Brazilian Portuguese, headword, IPA, explanation, usage
note, inflected forms, two bilingual examples and up to three other senses.

- The fixed instructions and the page text are prompt-cache breakpoints, so
  further lookups on the same page reread them at a fraction of the input price.
- The meaning is the first field and streams into the card before the rest.
- `Leitor.Dictionary.Pronunciation` turns the IPA into a Brazilian Portuguese
  pronunciation hint (for example `water` → `UÓ-râr`) with deterministic rules,
  without another model call.
- Completed cards are stored in `dictionary_cards`, keyed by model, prompt
  version, selection and paragraph, so repeating a lookup costs nothing.

Lookups are reading help: each one goes through
`Leitor.AI.prepare/2` like Define and Explain, so it uses the shared model
(Haiku) or, with a personal Anthropic key, the reader's chosen reading model,
and its usage is measured with the reader's other AI activity.

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

Reading appearance controls and the account menu use `@floating-ui/dom`,
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

### Page editing

Closing an editor with unsaved changes asks before leaving; reload/close uses
the browser's native confirmation. Same-document browser Back can bypass those
prompts, so an account/page-scoped session-storage backup recovers unsaved text
when reopening that editor in the same tab. The recovery notice makes it clear
that Save & read is still required. Explicitly discarding a draft or successfully
saving it clears its backup; failed saves keep it. Drafts are not synchronized
between tabs or devices, and recovery never replaces a newer saved document.

Readers remember a source block and relative offset in local storage, scoped to
the account, page, and saved body revision. This restores the passage after
reopening, including after a viewport/font change. A notebook reference or URL
fragment takes priority; editing/saving resets the reading position. Blocked
browser storage does not prevent reading or saving pages.

Pages use an inline Tiptap editor with Markdown persistence and sanitized MDEx
rendering. Type `/` at the start of a paragraph for headings, lists, checklists,
quotes, code, and dividers. Choose with arrow keys and Enter; Escape dismisses
the menu. Markdown shortcuts and pasted Markdown render as you type.
Cmd/Ctrl+Z undoes changes and Cmd/Ctrl+S saves the page.

Choose **Generate with AI** in the `/` menu (or type `/ai`) to describe new text
to insert at the cursor. The request uses the current title and up to 24,000
characters of draft context with `LEITOR_FEEDBACK_MODEL`. Instructions follow the
requested language and are limited to 2,000 characters. The generated Markdown
is inserted into the unsaved draft and can be undone. Escape or the header's Stop
button cancels a pending request; failures keep the prompt for retry.
The existing Claude API key is required, and credentials stay on the server.
ReqLLM streams Markdown through `stream_text/3` and `StreamResponse.process_stream/2`.
The prompt popup closes when generation starts. The shared loading animation and
incoming formatted text appear directly at the cursor, using the document's
typography. While writing, **Stop** in the header or Escape cancels the request.
The editor is read-only and saving is disabled until generation ends. Provisional
text is a document decoration, so cancellation leaves the draft and undo history intact.
Only a normally completed, nonempty response within 12,000 characters is inserted
into the editor. Interrupted, truncated, or failed responses leave the draft intact.

Page content is untrusted Markdown: MDEx sanitizes HTML, escapes raw tags, and
never compiles HEEx or evaluates Phoenix components. Shared Markdown parsing and
block-menu components remain in use by the page editor.

Run browser regression tests against a development server using
`npm --prefix assets run test:browser` (install Chromium once with
`cd assets && npx playwright install chromium`). Set `BASE_URL` for another port.
Tests create isolated accounts through the development mailbox; no external email
is sent. Screenshots and browser artifacts are written to the ignored `tmp/` folder.

### Account language and AI preferences

Open **Account → Preferences** (`/settings`) to choose English or Brazilian
Portuguese for the interface. Phoenix Gettext owns the interface catalogs in
`priv/gettext`; user page titles, text, and annotations retain their original
content. The public authentication screens reuse the last browser locale.

The AI response language is independent: follow the request (the existing
behavior), English, or Brazilian Portuguese. Explicit language requests take
priority. Existing answers are preserved; new requests use the current account
preferences, including requests from an already-open reading tab.

Reading/explanations and writing/generation have separate Claude model choices:
Haiku 5.5, Sonnet 5.5, and Opus 5.5. **Application default** retains the server's
`LEITOR_ANALYSIS_MODEL` / `LEITOR_FEEDBACK_MODEL` configuration. Credentials stay
on the server; preferences never store an API key or change authentication tokens.

The workspace and account dropdowns use shared `dropdown_item/1` rows inside
the Floating UI popover. They share compact spacing, Lucide icons, regular
labels, selected-state checks, and theme colors. Arrow keys and Home/End move
between entries; Enter/Space activates an entry. Escape restores trigger focus,
Tab leaves the menu, and outside clicks dismiss it.

Single-choice form fields use the same popup surface through the shared input
component. The native select retains its name, options, required/disabled state,
and LiveView form events; an ignored browser picker supplies the visible
control and listbox. Selection checks, keyboard search and arrows, Escape, and
viewport placement work in nested filter popups as well as account preferences.
Without JavaScript, the native select remains visible.

Reading typography follows Gloss's prose scale: the default is 20px, with
line-height choices of 1.50, 1.64, and 1.82. At widths up to 640px, line-height
is reduced by 0.05 for every reading face. Font-specific size ratios and the
0.95em paragraph gap match the reference; existing saved sizes remain intact.
Reset text settings to apply the current defaults.

## Creative pages and personal AI keys

The `/` menu generates interactive mechanisms, scientific diagrams and explanatory
illustrations. Other creative formats are shown as **Coming soon**. An isolated
program author runs locally and through a separate private Fly checker in production:
Claude writes original geometry, simulation and controls, the container compiles
and browser-tests them, and a screenshot review may request a rewrite. Accepted
`anatomy-program@1` references load private immutable artifacts in sandboxed
iframes. The generated code cannot access the reader's session or provider keys.
Build the separate runner image before using it; see [the figure guide](guides/figures.md).
Generation survives browser disconnection. Recover a running or completed attempt
from the page, and use **Adjust with AI** on an existing figure to refine it while
preserving its passing mechanical tests and surrounding text.
**Versions** previews and restores related accepted versions without another AI
charge. Save the page to keep a restoration. Busy requests can wait in a bounded,
uncharged queue; account preferences show actual tokens, estimated API costs,
duration and outcomes. See [AI usage](guides/ai-usage.md) and the
[six-case quality report](guides/figure-quality-report.md) for measurement limits
and observed generation results.

Without the program runner, generations use `anatomy-scene@1`: the model
specifies an original object's solids, positions, orientations, dimensions,
assembly offsets and rotation. No predefined factory or workbench is used.
Anatomy's MIT-licensed projection and lathe helpers construct and shade the
geometry. Inspect individual parts, open the assembly, turn the camera and
control motion. Existing workbench pages remain compatible with `anatomy-flow@1`.

A `leitor-figure` fence stores a compact validated blueprint with the page.
The registry separates data contracts and browser lifecycle from generation.
See [the figure guide](guides/figures.md) for the primitive vocabulary, budgets
and current limitations. The data-only engine is geometric composition; the
program engine authors and reviews real code, with bounded attempts and runtime.
Neither guarantees physical correctness. The slash menu's
Example figure is explicitly a preset; AI generation builds its own composition.
Existing SVG and animated-scene documents remain readable and editable.

Preferences include encrypted account provider keys and future image/narration
model choices. SVG is active; external image generation and narration are not
enabled yet. Shared text generation uses Haiku with daily account/global limits.
A personal Anthropic key unlocks the other supported Claude models without
spending the shared allowance. See [deployment configuration](guides/deployment.md#account-ai-budgets-and-provider-keys).

For an explicitly authorized development account, the operator task can import the
configured application key into that account's encrypted personal vault and select
its writing model. It is unavailable in test and production and prints no key:

```sh
mise exec -- mix leitor.ai.configure --user-id UUID --use-application-key --writing-model anthropic:claude-opus-5-5
```

For reproducible visual review in development, `mix leitor.ai.preview --user-id
UUID --brief tmp/brief.txt --title "Visual study" --format visual_explainer`
uses the same scoped authorization and selected model as the editor. It preserves
the provisional Markdown under ignored `tmp/` for diagnosis and creates a private
page only after complete validation. This contacts the provider and consumes an
attempt; it does not run as part of tests.

## License

Leitor is MIT licensed; see [LICENSE](LICENSE). Third-party code and fonts retain
their own notices. The bundled Anatomy kit is MIT licensed, with its upstream
notice and pinned provenance in `assets/vendor/anatomy/`.
