// A block and relative offset survive font/viewport changes better than pixels.
// Keep positions private to the account, page, and exact saved text revision.
export class ReadingPosition {
  constructor(root) {
    this.root = root
    this.key = `leitor:reading-position:${root.dataset.readingKey}`
    this.version = root.dataset.readingVersion
    this.ready = false
    this.interrupt = () => {this.interrupted = true}
    this.scroll = () => {
      if (!this.ready) return
      cancelAnimationFrame(this.measureFrame)
      this.measureFrame = requestAnimationFrame(() => {
        this.current = this.snapshot()
        clearTimeout(this.timer)
        this.timer = setTimeout(() => this.write(), 250)
      })
    }
    this.flush = () => {
      if (!this.ready) return
      if (this.root.isConnected) this.current = this.snapshot()
      this.write()
    }
    window.addEventListener('scroll', this.scroll, {passive:true})
    window.addEventListener('pagehide', this.flush)
    window.addEventListener('phx:page-loading-start', this.flush)
    for (const name of ['wheel', 'touchstart', 'pointerdown', 'keydown']) window.addEventListener(name, this.interrupt, {passive:true})
    document.fonts.ready.then(() => {
      if (this.destroyed) return
      this.restoreFrame = requestAnimationFrame(() => {
        this.restoreFrame = requestAnimationFrame(() => this.restore())
      })
    })
  }
  snapshot() {
    if (scrollY < 160) return {version:this.version, top:true}
    const blocks = [...this.root.querySelectorAll('[data-page-block]')]
    const block = blocks.find(el => el.getBoundingClientRect().bottom > 80) || blocks.at(-1)
    if (!block) return null
    const rect = block.getBoundingClientRect()
    return {version:this.version, block:Number(block.dataset.pageBlock), fraction:Math.max(0, Math.min(1, (80 - rect.top) / Math.max(1, rect.height)))}
  }
  restore() {
    if (this.destroyed) return
    let saved
    try {saved = JSON.parse(localStorage.getItem(this.key))} catch (_) {}
    const targeted = location.hash || new URLSearchParams(location.search).has('mark')
    if (!this.interrupted && !targeted && saved?.version === this.version) {
      if (saved.top === true) window.scrollTo({top:0, behavior:'instant'})
      else if (Number.isInteger(saved.block) && saved.block >= 0 && Number.isFinite(saved.fraction) && saved.fraction >= 0 && saved.fraction <= 1) {
        const block = this.root.querySelector(`[data-page-block="${saved.block}"]`)
        if (block) {
          const rect = block.getBoundingClientRect()
          window.scrollTo({top:Math.max(0, scrollY + rect.top + rect.height * saved.fraction - 80), behavior:'instant'})
        }
      }
    }
    this.ready = true
    this.current = this.snapshot()
  }
  reset() {
    this.interrupt()
    this.ready = true
    this.current = {version:this.version, top:true}
    this.write()
  }
  write() {
    clearTimeout(this.timer)
    if (this.current) try {localStorage.setItem(this.key, JSON.stringify(this.current))} catch (_) {}
  }
  destroy() {
    this.destroyed = true
    cancelAnimationFrame(this.restoreFrame)
    cancelAnimationFrame(this.measureFrame)
    this.flush()
    clearTimeout(this.timer)
    window.removeEventListener('scroll', this.scroll)
    window.removeEventListener('pagehide', this.flush)
    window.removeEventListener('phx:page-loading-start', this.flush)
    for (const name of ['wheel', 'touchstart', 'pointerdown', 'keydown']) window.removeEventListener(name, this.interrupt)
  }
}
