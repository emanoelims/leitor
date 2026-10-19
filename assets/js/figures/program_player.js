import {t} from '../i18n'
import {composeFigureStyle} from './kit/environment.mjs'

// Only an owned or explicitly shared, reviewed artifact can reach this player. Program code
// executes in an opaque-origin sandbox, never in the Phoenix page's realm.
export function mountProgram(element,blueprint) {
  const stage=element.querySelector('.figure-stage'),abort=new AbortController()
  const iframe=document.createElement('iframe')
  iframe.title=blueprint.title
  iframe.loading='lazy'
  iframe.sandbox='allow-scripts'
  iframe.referrerPolicy='no-referrer'
  iframe.setAttribute('allow',"camera 'none'; microphone 'none'; geolocation 'none'; clipboard-read 'none'; clipboard-write 'none'")
  iframe.className='figure-program-frame'
  const status=document.createElement('p');status.textContent=t('Drawing illustration…');status.setAttribute('role','status')
  stage.replaceChildren(status)
  let disposed=false,visible=true
  const environment=()=>iframe.contentWindow?.postMessage({type:'leitor:environment',theme:['dark','ink'].includes(document.documentElement.dataset.theme)?'dark':'light',visible:visible&&!document.hidden},'*')
  const observer=new MutationObserver(environment);observer.observe(document.documentElement,{attributes:true,attributeFilter:['data-theme']})
  const intersection=new IntersectionObserver(entries=>{visible=entries.at(-1).isIntersecting;environment()});intersection.observe(element)
  const message=event=>{
    if(event.source!==iframe.contentWindow||event.data?.type!=='leitor:height')return
    const height=Number(event.data.height)
    if(Number.isFinite(height))iframe.style.height=`${Math.max(320,Math.min(1400,height+8))}px`
  }
  window.addEventListener('message',message);document.addEventListener('visibilitychange',environment)
  iframe.addEventListener('load',environment)
  fetch(`${element.closest('[data-shared-figures]')?.dataset.sharedFigures || "/figures"}/${encodeURIComponent(blueprint.artifact_id)}`,{credentials:'same-origin',signal:abort.signal,headers:{accept:'application/json'}})
    .then(async response=>{
      if(!response.ok)throw Error('Unavailable')
      const artifact=await response.json()
      const bytes=Uint8Array.from(atob(artifact.bundle),c=>c.charCodeAt(0))
      const digest=new Uint8Array(await crypto.subtle.digest('SHA-256',bytes))
      const hex=[...digest].map(x=>x.toString(16).padStart(2,'0')).join('')
      if(hex!==artifact.digest)throw Error('Invalid artifact')
      const hash=btoa(String.fromCharCode(...digest))
      const bundle=new TextDecoder().decode(bytes)
      const style=composeFigureStyle(artifact.style,artifact.custom_style||'')
      if(/<\/script/i.test(bundle)||/<\/style/i.test(style))throw Error('Invalid document')
      const theme=['dark','ink'].includes(document.documentElement.dataset.theme)?'dark':'light'
      const policy=`default-src 'none'; script-src 'sha256-${hash}'; style-src 'unsafe-inline'; img-src data:; connect-src 'none'; frame-src 'none'; worker-src 'none'; form-action 'none'; base-uri 'none'; object-src 'none'`
      iframe.srcdoc=`<!doctype html><html data-theme="${theme}"><head><meta charset="utf-8"><meta http-equiv="Content-Security-Policy" content="${policy}"><meta name="viewport" content="width=device-width,initial-scale=1"><style>${style}</style></head><body><main id="figure-root"></main><script>${bundle}</script></body></html>`
      if(!disposed)stage.replaceChildren(iframe)
    }).catch(error=>{if(error.name!=='AbortError'&&!disposed)status.textContent=t('Illustration unavailable')})
  return()=>{disposed=true;abort.abort();observer.disconnect();intersection.disconnect();window.removeEventListener('message',message);document.removeEventListener('visibilitychange',environment);iframe.remove()}
}
