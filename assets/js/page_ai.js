import {t} from "./i18n"
import {computePosition, flip, offset, shift} from '@floating-ui/dom'
import {closeHistory} from '@tiptap/pm/history'
import {Decoration, DecorationSet} from '@tiptap/pm/view'

export class PageAI {
  constructor(hook) {
    this.hook = hook
    this.editor = hook.editor
    this.panel = hook.el.querySelector('#page-ai-composer')
    this.prompt = this.panel.querySelector('#page-ai-prompt')
    this.generate = this.panel.querySelector('#page-ai-generate')
    this.error = this.panel.querySelector('#page-ai-error')
    this.click = event => {
      if (event.target.closest('#page-ai-close')) this.close()
      else if (event.target.closest('#page-ai-generate')) this.submit()
    }
    this.keydown = event => {
      if (event.isComposing) return
      if (event.key === 'Escape') {event.preventDefault(); event.stopPropagation(); this.close()}
      if (event.target === this.prompt && event.key === 'Enter' && !event.shiftKey) {event.preventDefault(); this.submit()}
    }
    this.escape = event => {
      if (this.requestId && event.key === 'Escape') {event.preventDefault(); this.close()}
    }
    this.dismiss = event => {if (!this.panel.hidden && !this.panel.contains(event.target)) this.close(false)}
    this.blur = event => {if (!this.panel.hidden && event.relatedTarget && !this.panel.contains(event.relatedTarget)) this.close(false)}
    this.panel.addEventListener('click', this.click)
    this.panel.addEventListener('keydown', this.keydown)
    this.panel.addEventListener('focusout', this.blur)
    window.addEventListener('pointerdown', this.dismiss)
    window.addEventListener('keydown', this.escape)
    hook.handleEvent('page-ai-result', result => this.result(result))
    hook.handleEvent('page-ai-chunk', chunk => this.chunk(chunk))
    hook.handleEvent('page-ai-stopped', ({request_id}) => {
      if (request_id === this.requestId) {this.requestId = null; this.close()}
    })
  }
  open(range) {
    this.editor.chain().deleteRange(range).run()
    this.insertion = range.from
    this.prompt.value = ''
    this.error.hidden = true
    this.showPrompt()
  }
  showPrompt() {
    this.panel.style.visibility = 'hidden'
    this.panel.hidden = false
    this.prompt.disabled = false
    this.generate.disabled = false
    this.position(true)
  }
  position(focus = false) {
    if (this.panel.hidden || this.editor.isDestroyed) return
    const rect = this.editor.view.coordsAtPos(this.insertion)
    const reference = {contextElement: this.editor.view.dom, getBoundingClientRect: () => new DOMRect(rect.left, rect.top, rect.right - rect.left, rect.bottom - rect.top)}
    computePosition(reference, this.panel, {strategy: 'fixed', placement: 'bottom-start', middleware: [offset(8), flip(), shift({padding: 12})]}).then(({x, y}) => {
      if (!this.panel.hidden) {
        Object.assign(this.panel.style, {left: `${x}px`, top: `${y}px`, visibility: 'visible'})
        if (focus) this.prompt.focus({preventScroll: true})
      }
    })
  }
  submit() {
    if (this.requestId) return
    const prompt = this.prompt.value.trim()
    if (!prompt) {this.showError(t('Describe what you’d like to write.')); this.prompt.focus(); return}
    this.error.hidden = true
    this.requestId = crypto.randomUUID()
    this.panel.hidden = true
    this.prompt.disabled = true
    this.generate.disabled = true
    this.inline = document.createElement('div')
    this.inline.id = 'page-ai-inline'
    this.inline.className = 'page-ai-inline'
    this.inline.setAttribute('contenteditable', 'false')
    this.inline.setAttribute('aria-busy', 'true')
    this.inline.append(this.panel.querySelector('#page-ai-waiting').content.cloneNode(true))
    this.editor.view.dom.classList.add('is-ai-generating')
    this.editor.view.dom.setAttribute('aria-busy', 'true')
    this.editor.setEditable(false, false)
    this.editor.view.dispatch(this.editor.state.tr.setMeta('addToHistory', false))
    document.getElementById('page-save').disabled = true
    this.hook.pushEvent('generate-page-text', {
      request_id: this.requestId, prompt,
      title: document.getElementById('page-title').value,
      context: this.editor.getMarkdown().slice(0, 24000)
    })
  }
  decorations(doc) {
    return this.inline ? DecorationSet.create(doc, [Decoration.widget(this.insertion, this.inline, {key: this.requestId, side: -1})]) : DecorationSet.empty
  }
  clearInline() {
    this.inline = null
    if (this.editor.isDestroyed) return
    this.editor.view.dom.classList.remove('is-ai-generating')
    this.editor.view.dom.removeAttribute('aria-busy')
    this.editor.setEditable(true, false)
    this.editor.view.dispatch(this.editor.state.tr.setMeta('addToHistory', false))
    const save = document.getElementById('page-save')
    if (save) save.disabled = false
  }
  result({request_id, markdown, error}) {
    if (request_id !== this.requestId || this.editor.isDestroyed) return
    this.requestId = null
    this.clearInline()
    if (error) {this.showPrompt(); this.showError(t(error)); return}
    if (this.editor.getMarkdown().length + markdown.length > 300000) {
      this.showPrompt(); this.showError(t('This page is too long to add more text. Shorten it and try again.')); return
    }
    this.editor.view.dispatch(closeHistory(this.editor.state.tr))
    this.editor.chain().focus().setTextSelection(this.insertion).insertContent(markdown, {contentType: 'markdown'}).run()
  }
  chunk({request_id, html}) {
    if (request_id !== this.requestId || !this.inline) return
    this.inline.innerHTML = html
  }
  showError(message) {this.error.textContent = message; this.error.hidden = false; this.position()}
  close(focus = true) {
    if (this.requestId) this.hook.pushEvent('cancel-page-generation', {request_id: this.requestId})
    this.requestId = null
    this.panel.hidden = true
    this.clearInline()
    if (focus && !this.editor.isDestroyed) this.editor.chain().setTextSelection(this.insertion).focus().run()
  }
  destroy() {
    this.clearInline()
    this.panel.removeEventListener('click', this.click)
    this.panel.removeEventListener('keydown', this.keydown)
    this.panel.removeEventListener('focusout', this.blur)
    window.removeEventListener('pointerdown', this.dismiss)
    window.removeEventListener('keydown', this.escape)
  }
}
