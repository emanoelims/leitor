import {t} from './i18n'

export class UnsavedChanges {
  constructor(changed, discard) {
    this.unload = event => {
      if (!changed()) return
      event.preventDefault()
      event.returnValue = ''
    }
    this.leave = event => {
      const link = event.target.closest('a[href]')
      if (!link || event.defaultPrevented || event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey || link.target === '_blank' || link.hasAttribute('download')) return
      const destination = new URL(link.href, location.href)
      if (!['http:', 'https:'].includes(destination.protocol) || (destination.hash && destination.pathname === location.pathname && destination.search === location.search)) return
      if (changed()) {
        if (window.confirm(t('Leave without saving? Your changes will be lost.'))) discard()
        else {event.preventDefault(); event.stopImmediatePropagation()}
      }
    }
    window.addEventListener('beforeunload', this.unload)
    document.addEventListener('click', this.leave, true)
  }
  destroy() {
    window.removeEventListener('beforeunload', this.unload)
    document.removeEventListener('click', this.leave, true)
  }
}
