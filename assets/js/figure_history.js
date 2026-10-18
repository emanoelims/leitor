import {computePosition, flip, offset, shift, autoUpdate} from '@floating-ui/dom'
import {closeHistory} from '@tiptap/pm/history'
import {mountScenes, destroyScenes} from './scene_player'
import {replacementRange} from './figures/revision.mjs'
import {t} from './i18n'

export class FigureHistory {
  constructor(hook) {
    this.hook = hook
    this.panel = document.createElement('section')
    this.panel.className = 'figure-history'
    this.panel.id = 'figure-history'
    this.panel.hidden = true
    this.panel.setAttribute('role', 'dialog')
    this.panel.setAttribute('aria-label', t('Figure versions'))
    hook.el.append(this.panel)
    this.outside = event => {if (!this.panel.hidden && !this.panel.contains(event.target) && !this.trigger?.contains(event.target)) this.close(false)}
    this.escape = event => {if (!this.panel.hidden && event.key === 'Escape') {event.preventDefault(); event.stopPropagation(); this.close()}}
    window.addEventListener('pointerdown', this.outside)
    this.panel.addEventListener('keydown', this.escape)
  }
  open(source, from, trigger) {
    if (this.hook.ai.requestId) return
    let reference
    try {reference = JSON.parse(source)} catch (_) {return}
    if (reference.engine !== 'anatomy-program') return
    this.close(false)
    this.current = reference.artifact_id
    this.from = from
    this.trigger = trigger
    const request = this.request = crypto.randomUUID()
    const title = document.createElement('h3'), close = document.createElement('button'), header = document.createElement('header')
    title.textContent = t('Figure versions')
    close.type = 'button'; close.textContent = '×'; close.setAttribute('aria-label', t('Close'))
    close.onclick = () => this.close()
    header.append(title, close)
    this.list = document.createElement('div'); this.list.className = 'figure-history-list'
    this.preview = document.createElement('div'); this.preview.className = 'figure-history-preview'
    this.notice = document.createElement('p'); this.notice.setAttribute('role', 'status'); this.notice.textContent = t('Loading versions…')
    this.panel.replaceChildren(header, this.list, this.preview, this.notice)
    this.panel.hidden = false; this.panel.style.visibility = 'hidden'
    this.cleanupPosition = autoUpdate(trigger, this.panel, () => {
      computePosition(trigger, this.panel, {strategy: 'fixed', placement: 'bottom-start', middleware: [offset(8), flip(), shift({padding: 12})]}).then(({x,y}) => {
        if (this.request === request) Object.assign(this.panel.style, {left:`${x}px`,top:`${y}px`,visibility:'visible'})
      })
    })
    this.hook.pushEvent('figure-history', {artifact_id:this.current}, ({versions}) => {
      if (this.request !== request) return
      this.notice.textContent = t(!versions.length ? 'This version is unavailable.' : versions.length > 1 ? 'Restoring changes only this figure. Save the page to keep it.' : 'New adjustments will appear here. Restoring uses no AI credits.')
      for (const version of versions) {
        const button = document.createElement('button')
        button.type = 'button'; button.className = 'figure-history-version'
        const date = document.createElement('span'), label = document.createElement('small')
        date.textContent = new Intl.DateTimeFormat(document.documentElement.lang, {dateStyle:'medium',timeStyle:'short'}).format(new Date(version.inserted_at))
        label.textContent = t(version.id === this.current ? 'Current version' : 'Preview version')
        button.append(date, label)
        button.onclick = () => this.select(version, request)
        this.list.append(button)
      }
      close.focus({preventScroll:true})
    })
  }
  select(version, request) {
    const selection = this.selection = Symbol()
    this.hook.pushEvent('restore-figure', {current_id:this.current,target_id:version.id}, result => {
      if (this.request !== request || this.selection !== selection) return
      destroyScenes(this.preview); this.preview.replaceChildren()
      this.panel.querySelector('[data-restore-version]')?.remove()
      if (result.error) {this.notice.textContent = t(result.error); return}
      this.hook.pushEvent('preview-artwork', {source:result.source,language:'leitor-figure'}, ({html}) => {
        if (this.request !== request || this.selection !== selection) return
        this.preview.innerHTML = html; mountScenes(this.preview)
      })
      if (version.id === this.current) return
      const restore = document.createElement('button')
      restore.type = 'button'; restore.dataset.restoreVersion = version.id; restore.className = 'workspace-header-action workspace-header-primary'
      restore.textContent = t('Restore this version')
      restore.onclick = () => {
        const editor = this.hook.editor, range = replacementRange(editor.state.doc, this.from, this.current)
        if (!range || this.hook.ai.requestId) {this.notice.textContent = t('The original figure changed. Your saved result is safe to recover.'); return}
        editor.view.dispatch(closeHistory(editor.state.tr))
        editor.chain().focus().insertContentAt(range, {type:'codeBlock',attrs:{language:'leitor-figure'},content:[{type:'text',text:result.source}]}).run()
        this.close(false)
      }
      this.panel.append(restore)
    })
  }
  close(focus = true) {
    this.request = null; this.cleanupPosition?.(); this.cleanupPosition = null
    destroyScenes(this.panel); this.panel.hidden = true
    if (focus && this.trigger?.isConnected) this.trigger.focus({preventScroll:true})
  }
  destroy() {
    this.close(false)
    window.removeEventListener('pointerdown', this.outside)
    this.panel.removeEventListener('keydown', this.escape)
    this.panel.remove()
  }
}
