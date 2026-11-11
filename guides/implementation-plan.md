# Pages workspace

## Product scope

The authenticated workspace contains the page library (`/` and `/pages`), a new
page (`/pages/new`), reading and editing (`/pages/:id`), a combined notebook
(`/notebook`) with notes and word jars (`?view=words`). `/vocabulary` redirects to
the words section. Each page also has its own notebook.
Account settings, registration, login, and confirmation follow Phoenix's generated
account flows. All product screens require login.

The earlier sentence reader, writing, lessons, practice, review, progress,
collaboration, generated resource screens, and component gallery have been
removed, including their routes. Existing database records and domain APIs remain
intact. Development dashboard and mailbox routes remain development tools.

## Boundaries

- Accounts owns registration, email-link login, sessions, and account email settings.
- Library owns private texts and document import.
- Pages owns page annotations, anchored selections, notebook queries, and exports.
- Learning owns collected vocabulary and grammatical word jars.
- Language provides requested definitions, explanations, simplifications, and answers
  through Anthropic. Reading and editing do not require a provider request.
- Study and historical learning APIs remain available in the domain layer without
  product routes.

## UI and state

`Layouts.app/1` owns the universal shell and account menu. Its `menu` slot is the
workspace context selector; `tabs` follows it with a divider and `tools` contains
contextual controls. Pages provides source tabs, Notebook provides notes / word
jar tabs, and both place search and filters inside a shared popover. Context
selection also offers a separate creation action. Wrapped header menus anchor
below the full header so they do not cover the second row of tabs.
Reader and editor headers replace workspace navigation with a close link to the
page shelf and the current title, keeping the local notebook, editing,
appearance, and keyboard tools on the right. Titles scale with reading size.

LiveViews own server state and use scoped contexts for persistence. Stream
collections with stable IDs and reset them when filtering. Browser hooks manage
selection, anchored cards, citation previews, the corner reading map, and editor
interactions with lifecycle cleanup. Floating UI positions shared popovers and
selection tools. Appearance preferences persist locally.

The reader uses the local Gloss reference for typography, themes, customization,
selection actions, margin connectors, and card motion. Paragraph numbers start
hidden. The bottom question toolbar is absent. The selection toolbar includes a highlighter
with yellow, green, blue and rose choices that expand inline on hover or keyboard
focus. Clicking applies the remembered color; touching uses visible swatches.
Existing highlights open the same toolbar for recoloring or erasing. Highlights persist with the page,
appear in both notebooks and the corner reading map, and can be removed from
the notebook. The last chosen color is remembered with local reading preferences.

## Verification

Test login requirements, ownership, unsupported routes, import validation, page
creation and editing, annotations, both notebooks, vocabulary, and provider errors.
Browser regressions cover desktop and mobile navigation, reading preferences,
selection, cards, citation jumps, and the minimap. Run `mix precommit` and
`mix test --cover --warnings-as-errors`; preserve the existing coverage floor.

## Import intake

The importer exposes one text surface with document attachment and drag-and-drop.
It derives a bounded title from EPUB/DOCX/PDF metadata or Markdown/plain-text
headings, with `Untitled` as the fallback. Import titles do not depend on filenames
or caller-supplied title fields. Pasted drafts survive validation and extraction
errors; removing an attachment makes the draft editable again.
