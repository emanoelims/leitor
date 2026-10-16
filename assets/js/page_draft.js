// Session storage keeps a recoverable draft for same-document Back navigation,
// where browsers cannot always show a beforeunload confirmation.
export class PageDraft {
  constructor(root, snapshot) {
    this.root = root
    this.snapshot = snapshot
    this.original = snapshot()
    this.key = `leitor:page-draft:${root.dataset.draftKey}`
    this.save = () => {
      if (this.discarded) return
      clearTimeout(this.timer)
      try {
        const draft = this.snapshot()
        if (JSON.stringify(draft) === JSON.stringify(this.original)) sessionStorage.removeItem(this.key)
        else sessionStorage.setItem(this.key, JSON.stringify({original:this.original, draft}))
      } catch (_) {}
    }
    this.input = () => {clearTimeout(this.timer);this.timer=setTimeout(this.save,250)}
    root.closest('form').addEventListener('input', this.input)
    window.addEventListener('pagehide', this.save)
  }
  recover() {
    try {
      const saved = JSON.parse(sessionStorage.getItem(this.key))
      if (JSON.stringify(saved?.original) !== JSON.stringify(this.original)) return null
      const draft = saved?.draft
      if (typeof draft?.title === 'string' && draft.title.length <= 180 && typeof draft?.body === 'string' && draft.body.length <= 300000) return draft
    } catch (_) {}
    return null
  }
  discard() {
    this.discarded = true
    clearTimeout(this.timer)
    try {sessionStorage.removeItem(this.key)} catch (_) {}
  }
  destroy() {
    this.save()
    clearTimeout(this.timer)
    this.root.closest('form')?.removeEventListener('input', this.input)
    window.removeEventListener('pagehide', this.save)
  }
}
