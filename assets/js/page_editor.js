import {t} from "./i18n"
import {Editor, Extension} from "@tiptap/core"
import {Plugin} from "@tiptap/pm/state"
import StarterKit from "@tiptap/starter-kit"
import {Markdown} from "@tiptap/markdown"
import TaskList from "@tiptap/extension-task-list"
import TaskItem from "@tiptap/extension-task-item"
import Placeholder from "@tiptap/extension-placeholder"
import {MarkdownLinks, WritingParagraph} from "./writing_markdown"
import {computePosition, flip, offset, shift} from "@floating-ui/dom"
import {PageAI} from "./page_ai"
import {UnsavedChanges} from "./unsaved_changes"
import {PageDraft} from "./page_draft"

export const PageEditor = {
  mounted() {
    this.input = this.el.querySelector('#page-body')
    this.menu = this.el.querySelector('#writing-block-menu')
    this.options = [...this.menu.querySelectorAll('[data-command]')]
    this.list = this.menu.querySelector('#writing-block-options')
    const aiPreview = Extension.create({
      name: 'pageAIStreaming',
      addProseMirrorPlugins: () => [new Plugin({props: {decorations: state => this.ai?.decorations(state.doc) ?? null}})]
    })
    this.editor = new Editor({
      element: this.el.querySelector('#page-editor-surface'),
      extensions: [StarterKit.configure({paragraph: false, heading: {levels: [1, 2, 3]}, underline: false, link: {openOnClick: false}}), Markdown, MarkdownLinks, WritingParagraph, TaskList, TaskItem.configure({nested: true}), Placeholder.configure({placeholder: t('Write anything, paste a text, or type / for blocks…')}), aiPreview],
      content: this.input.value, contentType: 'markdown',
      editorProps: {
        attributes: {class: 'page-prose page-rich-editor', role: 'textbox', 'aria-label': t('Your page text'), 'aria-multiline': 'true', spellcheck: 'false'},
        handleKeyDown: (_, e) => this.keydown(e),
        handlePaste: (_, e) => {
          const text = e.clipboardData?.getData('text/plain')
          if (!text || e.clipboardData.getData('text/html') || this.editor.isActive('codeBlock')) return false
          e.preventDefault(); this.editor.commands.insertContent(text, {contentType: 'markdown'}); return true
        }
      },
      onUpdate: () => {
        this.input.value = this.editor.isEmpty ? '' : this.editor.getMarkdown()
        this.input.dispatchEvent(new Event('input', {bubbles: true}))
        this.updateMenu()
      },
      onSelectionUpdate: () => this.updateMenu(), onBlur: () => this.closeMenu()
    })
    this.ai = new PageAI(this)
    const title = this.input.form.querySelector('#page-title')
    const originalTitle = title.value, originalBody = this.editor.isEmpty ? '' : this.editor.getMarkdown()
    const snapshot = () => ({title:title.value, body:this.editor.isEmpty ? '' : this.editor.getMarkdown()})
    this.draft = new PageDraft(this.el, snapshot)
    this.unsavedChanges = new UnsavedChanges(() => title.value !== originalTitle || snapshot().body !== originalBody || Boolean(this.ai.requestId), () => this.draft.discard())
    this.onInput = e => {if (e.target !== this.input) e.stopPropagation()}
    this.el.addEventListener('input', this.onInput)
    this.el.addEventListener('change', this.onInput)
    this.save = e => {
      if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === 's') {e.preventDefault(); if (!this.ai.requestId) this.input.form.requestSubmit(document.getElementById('page-save'))}
    }
    this.choose = e => {const button = e.target.closest('[data-command]'); if (button) {e.preventDefault(); e.stopPropagation(); this.execute(button.dataset.command)}}
    this.hover = e => {
      if (e.pointerType === 'touch') return
      const button = e.target.closest('[data-command]')
      const index = this.visible?.indexOf(button) ?? -1
      if (index >= 0 && index !== this.selected) {this.selected = index; this.highlight()}
    }
    this.dismiss = e => {if (!this.el.contains(e.target)) this.closeMenu()}
    this.position = () => {this.positionMenu(); this.ai.position()}
    this.menu.addEventListener('pointerdown', this.choose)
    this.menu.addEventListener('pointermove', this.hover)
    window.addEventListener('keydown', this.save)
    window.addEventListener('pointerdown', this.dismiss)
    window.addEventListener('resize', this.position)
    window.addEventListener('scroll', this.position, true)
    const recovered = this.draft.recover()
    if (recovered) {
      title.value = recovered.title
      this.editor.commands.setContent(recovered.body, {contentType:'markdown'})
      title.dispatchEvent(new Event('input', {bubbles:true}))
      this.el.querySelector('#page-draft-recovered').hidden = false
    }
  },
  keydown(e) {
    if (this.menu.hidden || e.isComposing) return false
    if (e.key === 'Escape') {this.closeMenu(); e.preventDefault(); return true}
    if (['ArrowDown','ArrowUp'].includes(e.key) && this.visible.length) {this.selected = (this.selected + (e.key === 'ArrowDown' ? 1 : -1) + this.visible.length) % this.visible.length; this.highlight(true); e.preventDefault(); return true}
    if (e.key === 'Enter' && this.visible.length) {this.execute(this.visible[this.selected].dataset.command); e.preventDefault(); return true}
    return false
  },
  updateMenu() {
    const {empty, $from} = this.editor.state.selection
    const query = $from.parent.textBetween(0, $from.parentOffset)
    if (!empty || $from.parent.type.name !== 'paragraph' || !/^\/[\p{L}0-9 ]*$/iu.test(query)) {this.closeMenu(); return}
    this.range = {from: $from.start(), to: $from.pos}
    const normalize = text => text.normalize('NFD').replace(/\p{Diacritic}/gu, '').toLowerCase()
    this.visible = this.options.filter(button => {button.hidden = !normalize(button.dataset.search).includes(normalize(query.slice(1))); return !button.hidden})
    this.selected = 0; this.menu.hidden = false
    this.el.querySelector('#writing-block-empty').hidden = this.visible.length > 0
    this.highlight(true); this.positionMenu()
  },
  highlight(scroll = false) {
    const active = this.visible[this.selected]
    this.options.forEach(button => button.setAttribute('aria-selected', String(button === active)))
    if (!scroll || !active) return
    const item = active.getBoundingClientRect(), list = this.list.getBoundingClientRect()
    if (item.top < list.top) this.list.scrollTop -= list.top - item.top
    else if (item.bottom > list.bottom) this.list.scrollTop += item.bottom - list.bottom
  },
  positionMenu() {
    if (this.menu.hidden || this.editor.isDestroyed) return
    const rect = this.editor.view.coordsAtPos(this.editor.state.selection.from)
    const reference = {contextElement: this.editor.view.dom, getBoundingClientRect: () => new DOMRect(rect.left, rect.top, rect.right - rect.left, rect.bottom - rect.top)}
    computePosition(reference, this.menu, {strategy:'fixed',placement:'bottom-start',middleware:[offset(8),flip(),shift({padding:12})]}).then(({x,y}) => {if (!this.menu.hidden) Object.assign(this.menu.style,{left:`${x}px`,top:`${y}px`})})
  },
  closeMenu() {this.menu.hidden = true},
  execute(command) {
    if (command === 'ai') {this.closeMenu(); this.ai.open(this.range); return}
    let chain = this.editor.chain().focus().deleteRange(this.range)
    if (/^h[123]$/.test(command)) chain = chain.setHeading({level:Number(command[1])})
    else chain = chain[{paragraph:'setParagraph',bullet:'toggleBulletList',ordered:'toggleOrderedList',task:'toggleTaskList',quote:'toggleBlockquote',code:'toggleCodeBlock',divider:'setHorizontalRule'}[command]]()
    chain.run(); this.closeMenu()
  },
  destroyed() {
    this.draft.destroy()
    this.unsavedChanges.destroy()
    this.ai.destroy()
    this.editor.destroy(); this.menu.removeEventListener('pointerdown',this.choose)
    this.menu.removeEventListener('pointermove',this.hover)
    this.el.removeEventListener('input',this.onInput); this.el.removeEventListener('change',this.onInput)
    window.removeEventListener('keydown',this.save); window.removeEventListener('pointerdown',this.dismiss)
    window.removeEventListener('resize',this.position); window.removeEventListener('scroll',this.position,true)
  }
}
