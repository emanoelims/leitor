import {mountScenes, destroyScenes} from "./scene_player"
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
    this.format = this.panel.querySelector('#page-ai-format')
    this.generate = this.panel.querySelector('#page-ai-generate')
    this.error = this.panel.querySelector('#page-ai-error')
    this.generateLabel = this.generate.querySelector('span') || this.generate
    this.retryPrompt = null
    this.retryFormat = null
    this.updateRetry = () => {
      const retry = this.retryPrompt === this.prompt.value.trim() && this.retryFormat === this.format.value
      this.generateLabel.textContent = t(retry ? 'Continue refining' : this.replacement ? 'Apply adjustments' : 'Generate')
    }
    this.click = event => {
      if (event.target.closest('#page-ai-close')) this.close()
      else if (event.target.closest('#page-ai-generate')) this.submit()
    }
    this.keydown = event => {
      if (event.isComposing || event.defaultPrevented) return
      if (event.key === 'Escape' && this.panel.querySelector('details[data-popover][open]')) return
      if (event.key === 'Escape') {event.preventDefault(); event.stopPropagation(); this.close()}
      if (event.target === this.prompt && event.key === 'Enter' && !event.shiftKey) {event.preventDefault(); this.submit()}
    }
    this.escape = event => {
      if (this.requestId && event.key === 'Escape') {event.preventDefault(); this.close()}
    }
    this.owns = target => this.panel.contains(target) || document.getElementById('page-ai-format-options')?.contains(target)
    this.dismiss = event => {if (!this.panel.hidden && !this.owns(event.target)) this.close(false)}
    this.blur = event => {if (!this.panel.hidden && event.relatedTarget && !this.owns(event.relatedTarget)) this.close(false)}
    this.panel.addEventListener('click', this.click)
    this.panel.addEventListener('keydown', this.keydown)
    this.panel.addEventListener('focusout', this.blur)
    this.prompt.addEventListener('input', this.updateRetry)
    this.format.addEventListener('change', this.updateRetry)
    window.addEventListener('pointerdown', this.dismiss)
    window.addEventListener('keydown', this.escape)
    hook.handleEvent('page-ai-result', result => this.result(result))
    hook.handleEvent('page-ai-recover', payload => this.recover(payload))
    hook.handleEvent('page-ai-chunk', chunk => this.chunk(chunk))
    hook.handleEvent('page-ai-stage', ({request_id,stage})=>{
      if(request_id!==this.requestId||!this.inline)return
      const labels={building:'Building the figure…',model:'Building the mechanism…',geometry:'Drawing the geometry…',figure:'Connecting the controls…',testing:'Testing the interaction…',reviewing:'Reviewing the result…',refining:'Refining the figure…'}
      let status=this.inline.querySelector('.figure-generation-stage')
      if(!status){status=document.createElement('p');status.className='figure-generation-stage';status.setAttribute('role','status');this.inline.append(status)}
      status.textContent=t(labels[stage]||'Drawing illustration…')
    })
    hook.handleEvent('page-ai-stopped', ({request_id}) => {
      if (request_id === this.requestId) {this.requestId = null; this.close()}
    })
  }
  open(range) {
    this.editor.chain().deleteRange(range).run()
    this.insertion = range.from
    this.replacement = null
    this.prompt.value = ''
    this.retryPrompt = null
    this.retryFormat = null
    this.updateRetry()
    this.error.hidden = true
    this.showPrompt()
  }
  refine(source, from, size) {
    let reference
    try {reference=JSON.parse(source)} catch (_) {return}
    if(reference.engine!=='anatomy-program'||!reference.artifact_id)return
    this.insertion=from
    this.replacement={id:reference.artifact_id,from,to:from+size}
    this.prompt.value='';this.retryPrompt=null;this.retryFormat=null
    this.error.hidden=true;this.updateRetry();this.showPrompt()
  }
  showPrompt() {
    this.panel.querySelector('[data-ai-title]').textContent=t(this.replacement?'Adjust with AI':'Generate with AI')
    this.panel.style.visibility = 'hidden'
    this.panel.hidden = false
    this.prompt.disabled = false
    this.format.disabled = false
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
    this.prepare()
    this.hook.pushEvent('generate-page-text', {
      request_id: this.requestId, prompt, format: this.format.value,
      title: document.getElementById('page-title').value,
      context: this.editor.getMarkdown().slice(0, 24000),
      draft_body: this.editor.getMarkdown(), document: this.editor.getJSON(), insertion: this.insertion,
      base_revision_id:this.replacement?.id, replace_from:this.replacement?.from, replace_to:this.replacement?.to
    })
  }
  prepare() {
    this.panel.hidden = true
    this.prompt.disabled = true
    this.format.disabled = true
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
  }
  recover({request_id, request, status, markdown, retryable}) {
    if(this.requestId)return
    const current=this.editor.getMarkdown()
    const unchanged=this.editor.isEmpty||current===request.draft_body
    if(this.editor.isEmpty && request.document){
      try{this.editor.commands.setContent(request.document)}catch(_){this.editor.commands.setContent(request.draft_body,{contentType:'markdown'})}
    }
    const title=document.getElementById('page-title')
    if(!title.value.trim()||title.value==='Untitled'){
      title.value=request.title;title.dispatchEvent(new Event('input',{bubbles:true}))
    }
    this.prompt.value=request.prompt;this.format.value=request.format
    this.format.dispatchEvent(new Event('change',{bubbles:true}))
    this.insertion=unchanged ? Math.min(request.insertion??1,this.editor.state.doc.content.size) : this.editor.state.selection.from
    this.replacement=request.base_revision_id ? {id:request.base_revision_id,from:request.replace_from,to:request.replace_to} : null
    this.retryPrompt=retryable?request.prompt:null;this.retryFormat=retryable?request.format:null
    this.updateRetry();this.error.hidden=true
    const artifact=markdown?.match(/"artifact_id"\s*:\s*"([a-f\d-]+)"/i)?.[1]
    if(artifact&&current.includes(artifact)){
      this.showPrompt();this.showError(t('This figure is already in your draft.'));return
    }
    if(status==='failed'){this.showPrompt();return}
    this.requestId=request_id;this.prepare()
    if(status==='ready')this.result({request_id,markdown})
  }
  decorations(doc) {
    return this.inline ? DecorationSet.create(doc, [Decoration.widget(this.insertion, this.inline, {key: this.requestId, side: -1})]) : DecorationSet.empty
  }
  clearInline() {
    if (this.inline) destroyScenes(this.inline)
    this.inline = null
    if (this.editor.isDestroyed) return
    this.editor.view.dom.classList.remove('is-ai-generating')
    this.editor.view.dom.removeAttribute('aria-busy')
    this.editor.setEditable(true, false)
    this.editor.view.dispatch(this.editor.state.tr.setMeta('addToHistory', false))
    const save = document.getElementById('page-save')
    if (save) save.disabled = false
  }
  result({request_id, markdown, error, retryable}) {
    if (request_id !== this.requestId || this.editor.isDestroyed) return
    this.requestId = null
    this.clearInline()
    if (error) {
      this.retryPrompt = retryable ? this.prompt.value.trim() : null
      this.retryFormat = retryable ? this.format.value : null
      this.updateRetry()
      this.showPrompt(); this.showError(t(error)); return
    }
    this.retryPrompt = null
    this.retryFormat = null
    this.updateRetry()
    if (this.editor.getMarkdown().length + markdown.length > 300000) {
      this.showPrompt(); this.showError(t('This page is too long to add more text. Shorten it and try again.')); return
    }
    this.editor.view.dispatch(closeHistory(this.editor.state.tr))
    if(this.replacement){
      const {from,id}=this.replacement
      const node=this.editor.state.doc.nodeAt(from)
      const fence=markdown.match(/```leitor-figure\s*\n[\s\S]*?\n```/)
      let reference
      try {reference=JSON.parse(node?.textContent)} catch (_) {}
      if(node?.type.name!=='codeBlock'||node.attrs.language!=='leitor-figure'||reference?.artifact_id!==id||!fence){
        this.showPrompt();this.showError(t('The original figure changed. Your saved result is safe to recover.'));return
      }
      this.editor.chain().focus().insertContentAt({from,to:from+node.nodeSize},fence[0],{contentType:'markdown'}).run()
      this.replacement=null
    }else this.editor.chain().focus().setTextSelection(this.insertion).insertContent(markdown, {contentType: 'markdown'}).run()
    this.hook.pushEvent('generation-applied',{request_id})
  }
  chunk({request_id, html}) {
    if (request_id !== this.requestId || !this.inline) return
    const next = document.createElement('div')
    next.innerHTML = html
    const existing = new Map()
    for (const figure of this.inline.querySelectorAll('[data-artwork-key]')) {
      const key = figure.dataset.artworkKey
      if (!existing.has(key)) existing.set(key, [])
      existing.get(key).push(figure)
    }
    for (const figure of next.querySelectorAll('[data-artwork-key]')) {
      const previous = existing.get(figure.dataset.artworkKey)?.shift()
      if (previous) figure.replaceWith(previous)
    }
    destroyScenes(this.inline)
    this.inline.replaceChildren(...next.childNodes)
    mountScenes(this.inline)
  }
  showError(message) {this.error.textContent = message; this.error.hidden = false; this.position()}
  close(focus = true) {
    if (this.requestId) this.hook.pushEvent('cancel-page-generation', {request_id: this.requestId})
    this.requestId = null
    this.panel.querySelectorAll("details[open]").forEach(details => {details.open=false})
    this.panel.hidden = true
    this.clearInline()
    if (focus && !this.editor.isDestroyed) this.editor.chain().setTextSelection(this.insertion).focus().run()
  }
  destroy() {
    this.clearInline()
    this.panel.removeEventListener('click', this.click)
    this.panel.removeEventListener('keydown', this.keydown)
    this.panel.removeEventListener('focusout', this.blur)
    this.prompt.removeEventListener('input', this.updateRetry)
    this.format.removeEventListener('change', this.updateRetry)
    window.removeEventListener('pointerdown', this.dismiss)
    window.removeEventListener('keydown', this.escape)
  }
}
