// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//
// If you have dependencies that try to import CSS, esbuild will generate a separate `app.css` file.
// To load it, simply add a second `<link>` to your `root.html.heex` file.

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {hooks as colocatedHooks} from "phoenix-colocated/leitor"
import {PageEditor} from "./page_editor"
import {PageReader, PagePopup, PageCitations, PageMargin, PageRail, preserveMarginPlacement} from "./page_reader"
import {Floating} from "./floating"
import {Select} from "./select"
import {ReadingAppearance} from "./reading_appearance"
import {initializeReadingTheme, setReadingTheme, toggleReadingTheme} from "./reading_theme"
import topbar from "../vendor/topbar"
import {t, setLocale} from "./i18n"

window.addEventListener('phx:locale-changed', ({detail}) => setLocale(detail))
window.addEventListener('phx:page-saved', ({detail}) => {
  try {sessionStorage.removeItem(`leitor:page-draft:${detail.key}`)} catch (_) {}
})

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const readingPreferences = () => {
  try {return JSON.parse(localStorage.getItem("leitor:reading-preferences") || "{}")} catch (_) {return {}}
}
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: () => ({_csrf_token: csrfToken, reading_preferences: readingPreferences(), locale: document.body.dataset.locale || 'en'}),
  dom: {onBeforeElUpdated: preserveMarginPlacement},
  hooks: {...colocatedHooks, PageEditor, PageReader, PagePopup, PageCitations, PageMargin, PageRail, Floating, Select, ReadingAppearance},
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({detail: reloader}) => {
    // Enable server log streaming to client.
    // Disable with reloader.disableServerLogs()
    reloader.enableServerLogs()

    // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
    //
    //   * click with "c" key pressed to open at caller location
    //   * click with "d" key pressed to open at function component definition location
    let keyDown
    window.addEventListener("keydown", e => keyDown = e.key)
    window.addEventListener("keyup", _e => keyDown = null)
    window.addEventListener("click", e => {
      if(keyDown === "c"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtCaller(e.target)
      } else if(keyDown === "d"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtDef(e.target)
      }
    }, true)

    window.liveReloader = reloader
  })
}


initializeReadingTheme()
window.addEventListener("leitor:theme", event => toggleReadingTheme(event.target.closest?.('button')))

window.addEventListener("phx:reading-preference", ({detail}) => {
  if (detail.key !== 'focus') {
    try {localStorage.setItem("leitor:reading-preferences", JSON.stringify({...readingPreferences(), [detail.key]: detail.value}))} catch (_) {}
  }
  if (detail.key === 'pen') document.documentElement.dataset.pen = detail.value
})
window.addEventListener("phx:reading-text-preferences-reset", ({detail}) => {
  try {localStorage.setItem("leitor:reading-preferences", JSON.stringify({...readingPreferences(), ...detail}))} catch (_) {}
})
window.addEventListener("leitor:set-theme", event => setReadingTheme(event.detail.theme, event.target.closest?.('[data-theme-choice]')))

window.addEventListener("phx:page-export", async ({detail}) => {
  const status = document.getElementById("page-export-status")
  try {
    if (detail.mode === "copy") {await navigator.clipboard.writeText(detail.markdown); if (status) status.textContent = t("Copied as Markdown.")}
    else {
      const url = URL.createObjectURL(new Blob([detail.markdown], {type:"text/markdown;charset=utf-8"}))
      const link = document.createElement("a"); link.href = url; link.download = "notebook.md"; link.click(); setTimeout(() => URL.revokeObjectURL(url), 1000)
      if (status) status.textContent = t("Notebook downloaded.")
    }
  } catch (_) {if (status) status.textContent = t("Clipboard unavailable. Use Download instead.")}
})

window.addEventListener("leitor:copy", async ({detail}) => {
  const status=document.getElementById(detail.status_id)
  try {await navigator.clipboard.writeText(detail.text);if(status)status.textContent=t("Copied.")}
  catch (_) {if(status)status.textContent=t("Clipboard unavailable. You can select and copy the text.")}
})
