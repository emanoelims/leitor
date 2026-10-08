export const ReaderKeyboard = {
  mounted() {
    this.lastWord = null
    this.onClick = e => {const word = e.target.closest('[id^="word-"]'); if (word) this.lastWord = word.id}
    this.onKey = e => {
      if (e.altKey || e.ctrlKey || e.metaKey || e.shiftKey || e.target.closest('input,textarea,select,[contenteditable], [role="dialog"]') || document.querySelector('[role="dialog"]')) return
      if (e.key === 'ArrowRight' || e.key === 'ArrowLeft') {
        e.preventDefault()
        this.pushEvent('move', {direction: e.key === 'ArrowRight' ? 'next' : 'previous'})
      }
    }
    this.onSelection = () => {
      const selection = window.getSelection()
      const sentence = this.el.querySelector('#current-sentence')
      if (selection && sentence?.contains(selection.anchorNode) && sentence.contains(selection.focusNode)) {
        const text = selection.toString().trim()
        if (text.length <= 200 && text.split(/\s+/).length > 1) this.pushEvent('select-expression', {text})
      }
    }
    this.el.addEventListener('mouseup', this.onSelection)
    this.el.addEventListener('click', this.onClick)
    window.addEventListener('keydown', this.onKey)
    this.handleEvent('restore-word-focus', () => document.getElementById(this.lastWord)?.focus())
  },
  destroyed() {
    this.el.removeEventListener('click', this.onClick)
    this.el.removeEventListener('mouseup', this.onSelection)
    window.removeEventListener('keydown', this.onKey)
    window.speechSynthesis?.cancel()
  }
}

export const ShadowingRecorder = {
  mounted() {
    this.button = this.el.querySelector('button')
    this.label = this.el.querySelector('.record-label')
    this.audio = this.el.querySelector('audio')
    this.status = this.el.querySelector('[role="status"]')
    this.onRecord = async () => {
      if (this.recorder?.state === 'recording') {this.button.disabled = true; this.recorder.stop(); return}
      this.button.disabled = true
      this.status.textContent = "Allow microphone access in your browser to start recording."
      try {
        this.stream = await navigator.mediaDevices.getUserMedia({audio: true})
        if (!this.el.isConnected) {this.stream.getTracks().forEach(t => t.stop()); return}
        this.chunks = []
        this.recorder = new MediaRecorder(this.stream)
        this.recorder.ondataavailable = e => {if (e.data.size) this.chunks.push(e.data)}
        this.recorder.onstop = () => {
          clearTimeout(this.timeout)
          this.stream.getTracks().forEach(t => t.stop())
          if (this.blobURL) URL.revokeObjectURL(this.blobURL)
          this.blobURL = URL.createObjectURL(new Blob(this.chunks, {type: this.recorder.mimeType}))
          this.audio.src = this.blobURL
          this.audio.hidden = false
          this.button.disabled = false
          this.label.textContent = 'Record again'
          this.status.textContent = 'Listen to your recording and compare it with the original. Audio stays on this device.'
          if (this.el.isConnected) this.pushEvent('recorded', {duration: Math.min(60, Math.max(1, Math.round((Date.now() - this.startedAt) / 1000)))})
        }
        this.startedAt = Date.now()
        this.recorder.start()
        this.label.textContent = 'Stop recording'
        this.status.textContent = 'Recording… up to 60 seconds.'
        this.timeout = setTimeout(() => {if (this.recorder.state === 'recording') {this.button.disabled = true; this.recorder.stop()}}, 60000)
      } catch (_) {
        this.stream?.getTracks().forEach(t => t.stop())
        this.status.textContent = 'Microphone unavailable. Allow microphone access in your browser, then try again.'
      } finally {this.button.disabled = false}
    }
    this.button.addEventListener('click', this.onRecord)
  },
  destroyed() {
    clearTimeout(this.timeout)
    this.button.removeEventListener('click', this.onRecord)
    if (this.recorder) {this.recorder.onstop = null; if (this.recorder.state === 'recording') this.recorder.stop()}
    this.stream?.getTracks().forEach(t => t.stop())
    if (this.blobURL) URL.revokeObjectURL(this.blobURL)
  }
}

export const WritingQuestion = {
  mounted() {
    this.sync = () => {this.el.querySelector('[name="tutor[text]"]').value = document.querySelector('#writing_text').value}
    this.el.addEventListener('submit', this.sync, true)
  },
  destroyed() {this.el.removeEventListener('submit', this.sync, true)}
}
