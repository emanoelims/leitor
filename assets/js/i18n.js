let translations = {}
try {translations = JSON.parse(document.body.dataset.i18n || '{}')} catch (_) {}
export const t = message => translations[message] || message
export const setLocale = ({locale, translations: messages}) => {
  translations = messages || {}
  document.documentElement.lang = locale === 'pt_BR' ? 'pt-BR' : 'en'
  document.body.dataset.locale = locale
  document.cookie = `leitor_locale=${encodeURIComponent(locale)}; path=/; max-age=31536000; SameSite=Lax`
}
