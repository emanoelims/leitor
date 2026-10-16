// Gloss SettingsMenu.pickTheme, adapted from the React store to Phoenix's
// browser preferences. Keep the chosen Auto mode separate from its palette.
const themes = ['auto', 'light', 'sepia', 'snow', 'dark', 'ink']
const systemTheme = matchMedia('(prefers-color-scheme: dark)')
let mode = 'auto'
let swap = null

export const themePreference = () => mode
const resolved = theme => theme === 'auto' ? systemTheme.matches ? 'dark' : 'light' : theme
const apply = theme => {
  mode = theme
  const root = document.documentElement
  root.dataset.themeMode = theme
  root.dataset.theme = resolved(theme)
  try {localStorage.setItem('leitor:theme', theme)} catch (_) {}
}

export const initializeReadingTheme = () => {
  let saved
  try {saved = localStorage.getItem('leitor:theme')} catch (_) {}
  apply(themes.includes(saved) ? saved : 'auto')
  try {
    const pen = JSON.parse(localStorage.getItem('leitor:reading-preferences') || '{}')?.pen
    document.documentElement.dataset.pen = ['vermilion', 'cobalt', 'moss', 'graphite'].includes(pen) ? pen : 'vermilion'
  } catch (_) {document.documentElement.dataset.pen = 'vermilion'}
  systemTheme.addEventListener('change', () => {if (mode === 'auto') apply('auto')})
}

export const setReadingTheme = (theme, origin) => {
  if (!themes.includes(theme)) return
  const root = document.documentElement
  if (!document.startViewTransition || matchMedia('(prefers-reduced-motion: reduce)').matches || resolved(theme) === root.dataset.theme || !origin) {
    swap?.skipTransition()
    apply(theme)
    return
  }
  const rect = origin.getBoundingClientRect(), width = innerWidth, height = innerHeight
  const x = rect.left + rect.width / 2, y = rect.top + 19
  const at = `${(x / width * 100).toFixed(2)}% ${(y / height * 100).toFixed(2)}%`
  const end = (Math.hypot(Math.max(x, width - x), Math.max(y, height - y)) / (Math.hypot(width, height) / Math.SQRT2) * 100).toFixed(2)
  swap?.skipTransition()
  root.classList.add('theme-swap')
  const transition = document.startViewTransition(() => apply(theme))
  swap = transition
  const passThrough = event => {
    if (event.target !== root) return
    event.stopPropagation()
    transition.skipTransition()
    const {clientX, clientY} = event
    transition.finished.finally(() => document.elementFromPoint(clientX, clientY)?.click())
  }
  document.addEventListener('click', passThrough, true)
  transition.ready.then(() => root.animate(
    {clipPath: [`circle(0% at ${at})`, `circle(${end}% at ${at})`]},
    {duration: 620, easing: 'cubic-bezier(0.22, 1, 0.36, 1)', pseudoElement: '::view-transition-new(root)'}
  )).catch(() => {})
  transition.finished.finally(() => {
    document.removeEventListener('click', passThrough, true)
    if (swap === transition) {swap = null; root.classList.remove('theme-swap')}
  })
}

export const toggleReadingTheme = origin => setReadingTheme(['dark', 'ink'].includes(document.documentElement.dataset.theme) ? 'light' : 'dark', origin)
