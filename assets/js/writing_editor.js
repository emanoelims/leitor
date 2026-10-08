const paragraphs = text => [...text.matchAll(/[^\n]+/g)].filter(match => match[0].trim())

export const WritingEditor = {
  mounted() {
    this.sync = () => {
      const parts = paragraphs(this.el.value)
      const cursor = this.el.selectionStart
      let index = parts.findIndex(part => cursor <= part.index + part[0].length)
      if (index < 0) index = Math.max(0, parts.length - 1)
      document.getElementById("writing-paragraph").value = index
      const questionIndex = document.querySelector('#writing-question [name="tutor[paragraph]"]')
      if (questionIndex) questionIndex.value = index
      if (this.index !== index) {
        this.index = index
        this.pushEvent("paragraph", {index})
      }
      this.resize()
    }
    this.resize = () => {
      this.el.style.height = "auto"
      this.el.style.height = `${this.el.scrollHeight}px`
    }
    this.apply = () => this.pushEvent("apply", {text: this.el.value})
    this.save = event => {
      if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === "s") {
        event.preventDefault()
        this.el.form.requestSubmit(document.getElementById("save-draft"))
      }
    }
    this.events = ["input", "click", "keyup", "select", "focus"]
    this.events.forEach(event => this.el.addEventListener(event, this.sync))
    this.el.addEventListener("writing:apply", this.apply)
    window.addEventListener("keydown", this.save)
    window.addEventListener("resize", this.resize)
    this.handleEvent("writing-applied", ({text, index}) => {
      this.el.value = text
      const start = paragraphs(text)[index]?.index || 0
      this.el.setSelectionRange(start, start)
      this.el.focus()
      this.sync()
    })
    this.handleEvent("writing-loaded", ({text}) => {
      this.el.value = text
      this.el.setSelectionRange(0, 0)
      this.el.focus()
      this.sync()
    })
    this.sync()
  },
  updated() { this.resize() },
  destroyed() {
    this.events.forEach(event => this.el.removeEventListener(event, this.sync))
    this.el.removeEventListener("writing:apply", this.apply)
    window.removeEventListener("keydown", this.save)
    window.removeEventListener("resize", this.resize)
  }
}
