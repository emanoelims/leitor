import {themePreference} from "./reading_theme"

// The panel is rendered by LiveView; this ignored controller keeps browser-owned
// theme state and tab keyboard navigation in sync with Gloss's appearance menu.
export const ReadingAppearance = {
  mounted() {
    this.panel = document.getElementById('reading-appearance-panel')
    this.syncTheme = () => {
      const theme = themePreference()
      this.panel.querySelectorAll('[data-theme-choice]').forEach(button => {
        const pressed = String(button.dataset.themeChoice === theme)
        if (button.getAttribute('aria-pressed') !== pressed) button.setAttribute('aria-pressed', pressed)
      })
    }
    this.key = event => {
      const tab = event.target.closest('[data-appearance-tab]')
      if (!tab || !['ArrowLeft', 'ArrowRight', 'Home', 'End'].includes(event.key)) return
      event.preventDefault()
      const tabs = [...this.panel.querySelectorAll('[data-appearance-tab]')]
      const index = tabs.indexOf(tab)
      const next = event.key === 'Home' ? 0 : event.key === 'End' ? tabs.length - 1 :
        (index + (event.key === 'ArrowRight' ? 1 : -1) + tabs.length) % tabs.length
      tabs[next].focus()
      tabs[next].click()
    }
    this.themeObserver = new MutationObserver(this.syncTheme)
    this.themeObserver.observe(document.documentElement, {attributes: true, attributeFilter: ['data-theme', 'data-theme-mode']})
    this.panelObserver = new MutationObserver(this.syncTheme)
    this.panelObserver.observe(this.panel, {childList: true, subtree: true, attributes: true, attributeFilter: ['aria-pressed']})
    this.panel.addEventListener('keydown', this.key)
    this.syncTheme()
  },
  destroyed() {
    this.themeObserver.disconnect()
    this.panelObserver.disconnect()
    this.panel.removeEventListener('keydown', this.key)
  }
}
