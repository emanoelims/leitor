import {Editor, Extension} from "@tiptap/core"
import {Plugin} from "@tiptap/pm/state"
import StarterKit from "@tiptap/starter-kit"
import {Markdown} from "@tiptap/markdown"
import TaskList from "@tiptap/extension-task-list"
import TaskItem from "@tiptap/extension-task-item"
import Placeholder from "@tiptap/extension-placeholder"
import {computePosition, flip, offset, shift} from "@floating-ui/dom"

const plainDocument = text => ({
  type: "doc",
  content: text.split("\n").map(line => ({type: "paragraph", ...(line ? {content: [{type: "text", text: line}]} : {})}))
})

export const WritingEditor = {
  mounted() {
    this.input = this.el.querySelector("#writing_text")
    this.format = this.el.querySelector("#writing-format")
    this.menu = this.el.querySelector("#writing-block-menu")
    this.options = [...this.menu.querySelectorAll("[data-command]")]
    const hook = this
    const limit = Extension.create({
      name: "draftLimit",
      addProseMirrorPlugins() {
        return [new Plugin({filterTransaction(transaction, state) {
          if (!transaction.docChanged || hook.loading) return true
          const serialize = doc => hook.editor.markdown.serialize(doc.toJSON())
          const valid = [...serialize(transaction.doc)].length <= 10000 || serialize(transaction.doc).length < serialize(state.doc).length
          if (!valid) hook.el.querySelector("#writing-editor-status").textContent = "The draft limit is 10,000 characters. Shorten the text to continue."
          return valid
        }})]
      }
    })
    this.editor = new Editor({
      element: this.el.querySelector("#writing-surface"),
      extensions: [StarterKit.configure({heading: {levels: [1, 2, 3]}, underline: false, link: {openOnClick: false}}), Markdown,
        TaskList, TaskItem.configure({nested: true}), Placeholder.configure({placeholder: "Write in English, or type / for blocks…"}), limit],
      content: this.format.value === "markdown" ? this.input.value : plainDocument(this.input.value),
      contentType: this.format.value === "markdown" ? "markdown" : "json",
      editorProps: {
        attributes: {class: "writing-prose writing-rich-editor", role: "textbox", "aria-label": "Your English text", "aria-multiline": "true", "aria-describedby": "writing-help", spellcheck: "false"},
        handleKeyDown: (_view, event) => this.keydown(event),
        handlePaste: (_view, event) => {
          const text = event.clipboardData?.getData("text/plain")
          if (!text || event.clipboardData.getData("text/html") || this.editor.isActive("codeBlock")) return false
          event.preventDefault()
          this.editor.commands.insertContent(text, {contentType: "markdown"})
          return true
        }
      },
      onUpdate: () => { this.sync(true); this.updateMenu() },
      onSelectionUpdate: () => { this.sync(false); this.updateMenu() }
    })
    this.sync = changed => {
      if (changed) {
        this.el.querySelector("#writing-editor-status").textContent = ""
        this.input.value = this.editor.getMarkdown()
        this.format.value = "markdown"
        this.input.dispatchEvent(new Event("input", {bubbles: true}))
      }
      const {$from} = this.editor.state.selection
      let index = -1, count = 0
      this.editor.state.doc.descendants((node, pos) => {
        if (!node.isTextblock || node.type.name === "codeBlock" || !node.textContent.trim()) return
        if ($from.pos >= pos && $from.pos <= pos + node.nodeSize) index = count
        count++
      })
      document.getElementById("writing-paragraph").value = index
      const questionIndex = document.querySelector('#writing-question [name="tutor[paragraph]"]')
      if (questionIndex) questionIndex.value = index
      if (this.index !== index) { this.index = index; this.pushEvent("paragraph", {index}) }
    }
    // Only the canonical Markdown field belongs to LiveView's form protocol.
    // In particular, task checkboxes must finish their editor transaction first.
    this.editorInput = event => { if (event.target !== this.input) event.stopPropagation() }
    this.el.addEventListener("input", this.editorInput)
    this.el.addEventListener("change", this.editorInput)
    this.apply = () => this.pushEvent("apply", {text: this.input.value, format: this.format.value})
    this.save = event => {
      if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === "s") {
        event.preventDefault()
        this.input.form.requestSubmit(document.getElementById("save-draft"))
      }
    }
    this.choose = event => {
      const button = event.target.closest("[data-command]")
      if (button) { event.preventDefault(); this.execute(button.dataset.command) }
    }
    this.dismiss = event => { if (!this.el.contains(event.target)) this.closeMenu() }
    this.position = () => this.positionMenu()
    this.el.addEventListener("writing:apply", this.apply)
    this.menu.addEventListener("pointerdown", this.choose)
    window.addEventListener("keydown", this.save)
    window.addEventListener("pointerdown", this.dismiss)
    window.addEventListener("resize", this.position)
    window.addEventListener("scroll", this.position, true)
    this.handleEvent("writing-loaded", ({text, format}) => this.load(text, format))
    this.handleEvent("writing-applied", ({text, index}) => this.load(text, this.format.value, index))
    this.sync(false)
  },
  load(text, format, index = 0) {
    this.loading = true
    try {
      this.editor.commands.setContent(format === "markdown" ? text : plainDocument(text), {contentType: format === "markdown" ? "markdown" : "json", emitUpdate: false})
    } finally {
      this.loading = false
    }
    this.el.querySelector("#writing-editor-status").textContent = ""
    this.input.value = text
    this.format.value = format || "plain"
    let count = 0, cursor = 1
    this.editor.state.doc.descendants((node, pos) => {
      if (!node.isTextblock || node.type.name === "codeBlock" || !node.textContent.trim()) return
      if (count++ === index) cursor = pos + 1
    })
    this.editor.commands.focus(cursor)
    this.sync(false)
    this.closeMenu()
  },
  keydown(event) {
    if (this.menu.hidden || event.isComposing) return false
    if (event.key === "Escape") { this.closeMenu(); event.preventDefault(); return true }
    if (["ArrowDown", "ArrowUp"].includes(event.key) && this.visible.length) {
      this.selected = (this.selected + (event.key === "ArrowDown" ? 1 : -1) + this.visible.length) % this.visible.length
      this.highlight(); event.preventDefault(); return true
    }
    if (event.key === "Enter" && this.visible.length) {
      this.execute(this.visible[this.selected].dataset.command); event.preventDefault(); return true
    }
    return false
  },
  updateMenu() {
    const {empty, $from} = this.editor.state.selection
    const query = $from.parent.textBetween(0, $from.parentOffset)
    if (!empty || $from.parent.type.name !== "paragraph" || !/^\/[a-z0-9 ]*$/i.test(query)) { this.closeMenu(); return }
    this.range = {from: $from.start(), to: $from.pos}
    this.visible = this.options.filter(button => {
      button.hidden = !button.dataset.search.includes(query.slice(1).toLowerCase())
      return !button.hidden
    })
    this.selected = 0
    this.menu.hidden = false
    this.el.querySelector("#writing-block-empty").hidden = this.visible.length > 0
    this.editor.view.dom.setAttribute("aria-controls", "writing-block-options")
    this.highlight()
    this.positionMenu()
  },
  highlight() {
    this.options.forEach(button => button.setAttribute("aria-selected", String(button === this.visible[this.selected])))
    const selected = this.visible[this.selected]
    if (selected) {
      this.editor.view.dom.setAttribute("aria-activedescendant", selected.id)
      const top = selected.offsetTop
      const bottom = top + selected.offsetHeight
      if (top < this.menu.scrollTop) this.menu.scrollTop = top
      else if (bottom > this.menu.scrollTop + this.menu.clientHeight) this.menu.scrollTop = bottom - this.menu.clientHeight
    } else this.editor.view.dom.removeAttribute("aria-activedescendant")
  },
  positionMenu() {
    if (this.menu.hidden || this.editor.isDestroyed) return
    const rect = this.editor.view.coordsAtPos(this.editor.state.selection.from)
    const reference = {
      contextElement: this.editor.view.dom,
      // DOMRect coordinates are prototype getters, so spreading rect loses them.
      getBoundingClientRect: () => new DOMRect(rect.left, rect.top, rect.right - rect.left, rect.bottom - rect.top)
    }
    computePosition(reference, this.menu, {strategy: "fixed", placement: "bottom-start", middleware: [offset(8), flip(), shift({padding: 12})]})
      .then(({x, y}) => { if (!this.menu.hidden) Object.assign(this.menu.style, {left: `${x}px`, top: `${y}px`}) })
  },
  closeMenu() {
    this.menu.hidden = true
    this.editor.view.dom.removeAttribute("aria-activedescendant")
    this.editor.view.dom.removeAttribute("aria-controls")
  },
  execute(command) {
    let chain = this.editor.chain().focus().deleteRange(this.range)
    if (/^h[123]$/.test(command)) chain = chain.setHeading({level: Number(command[1])})
    else {
      const actions = {paragraph: "setParagraph", bullet: "toggleBulletList", ordered: "toggleOrderedList", task: "toggleTaskList", quote: "toggleBlockquote", code: "toggleCodeBlock", divider: "setHorizontalRule"}
      chain = chain[actions[command]]()
    }
    chain.run()
    this.closeMenu()
  },
  destroyed() {
    this.el.removeEventListener("input", this.editorInput)
    this.el.removeEventListener("change", this.editorInput)
    this.el.removeEventListener("writing:apply", this.apply)
    this.menu.removeEventListener("pointerdown", this.choose)
    window.removeEventListener("keydown", this.save)
    window.removeEventListener("pointerdown", this.dismiss)
    window.removeEventListener("resize", this.position)
    window.removeEventListener("scroll", this.position, true)
    this.editor.destroy()
  }
}
