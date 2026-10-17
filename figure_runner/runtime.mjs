import {mount} from '/input/figure.mjs'
import * as checksModule from '/input/checks.mjs'

const root=document.getElementById('figure-root')
root.className='iso'
root.dataset.theme=document.documentElement.dataset.theme||'light'
const reduced=matchMedia('(prefers-reduced-motion: reduce)')
let dispose
try {
  const checks=Object.keys(checksModule).filter(name=>name==='verify'||/^verifyExtra[1-9][0-9]?$/.test(name)).sort().flatMap(name=>{
    const result=checksModule[name]()
    if(!Array.isArray(result))throw Error('Mechanical verifier must return an array: '+name)
    return result
  })
  if(typeof checksModule.verify!=='function')throw Error('Mechanical verifier must export verify()')
  if(!Array.isArray(checks)||checks.length>24)throw Error('Mechanical checks must return a bounded array')
  const names=new Set()
  for(const check of checks){
    if(typeof check?.name!=='string'||!check.name.trim()||check.name.length>160||names.has(check.name)||typeof check.passed!=='boolean')throw Error('Invalid mechanical check: '+String(check?.name).slice(0,160))
    names.add(check.name)
  }
  const results=checks.map(({name,passed,detail})=>({name,passed,...(typeof detail==='string'?{detail:detail.slice(0,300)}:{})}))
  document.documentElement.dataset.modelChecks=JSON.stringify(results)
  const failed=results.filter(check=>!check.passed)
  if(failed.length)throw Error('Mechanical checks failed: '+failed.map(check=>check.name+(check.detail?' ('+check.detail+')':'')).join('; '))
  dispose=mount(root,{reducedMotion:reduced.matches,theme:document.documentElement.dataset.theme||'light'})
  root.classList.add('iso')
  document.documentElement.dataset.ready='true'
} catch(error) {
  document.documentElement.dataset.error=String(error.message).slice(0,300)
  throw error
}
window.addEventListener('pagehide',()=>dispose?.())
window.addEventListener('message',event=>{
  if(event.source!==parent||event.data?.type!=='leitor:environment')return
  const theme=event.data.theme==='dark'?'dark':'light'
  document.documentElement.dataset.theme=theme
  root.dataset.theme=theme
  root.dispatchEvent(new CustomEvent('figure:environment',{detail:{theme,visible:event.data.visible===true,reducedMotion:reduced.matches}}))
})
let lastHeight=0
new ResizeObserver(()=>{
  const height=Math.ceil(root.getBoundingClientRect().height)
  if(height!==lastHeight){lastHeight=height;parent.postMessage({type:'leitor:height',height},'*')}
}).observe(root)
