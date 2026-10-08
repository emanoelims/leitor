import {autoUpdate, computePosition, flip, offset, shift, size} from "@floating-ui/dom"

// Adapted from Sisteo's Floating hook. The ignored controller owns no panel
// content: LiveView continues updating links, disabled states and labels.
export const Floating = {
  mounted() {
    this.disclosure = this.el.closest("details")
    this.reference = this.disclosure.querySelector("summary")
    this.panel = document.getElementById(this.el.dataset.panel)
    this.sync = () => {
      this.cleanup?.()
      this.cleanup = null
      this.generation = (this.generation || 0) + 1
      if (this.disclosure.open) {
        this.cleanup = autoUpdate(this.reference, this.panel, () => this.position())
      }
    }
    this.onToggle = () => this.sync()
    this.disclosure.addEventListener("toggle", this.onToggle)
    // LiveView may replace inline styles during a patch while the panel is open.
    this.observer = new MutationObserver(() => {
      if (this.disclosure.open && !this.panel.style.left) this.position()
    })
    this.observer.observe(this.panel, {attributes: true, attributeFilter: ["style"]})
    this.sync()
  },
  updated() {
    this.sync()
  },
  position() {
    const generation = this.generation
    computePosition(this.reference, this.panel, {
      strategy: "fixed",
      placement: this.el.dataset.placement || "bottom-start",
      middleware: [
        offset(12),
        flip({padding: 12}),
        shift({padding: 12}),
        size({padding: 12, apply: ({availableHeight, elements}) => {
          elements.floating.style.maxHeight = `${Math.max(0, availableHeight)}px`
        }})
      ]
    }).then(({x, y}) => {
      if (generation !== this.generation || !this.disclosure.open || !this.el.isConnected) return
      Object.assign(this.panel.style, {left: `${x}px`, top: `${y}px`})
    })
  },
  destroyed() {
    this.generation++
    this.cleanup?.()
    this.observer.disconnect()
    this.disclosure.removeEventListener("toggle", this.onToggle)
  }
}
