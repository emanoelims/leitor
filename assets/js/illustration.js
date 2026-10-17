import {mountScenes, destroyScenes, toggleScene} from "./scene_player"
import {Plugin, NodeSelection, TextSelection} from "@tiptap/pm/state"
import CodeBlock from "@tiptap/extension-code-block"
import {t} from "./i18n"

const languages = new Set(['leitor-svg', 'leitor-svg-float', 'leitor-svg-sway', 'leitor-svg-pulse', 'leitor-scene', 'leitor-figure'])
export const starterIllustration = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 800 400"><title>A quiet evening</title><rect width="800" height="400" fill="#1d2939"/><circle cx="620" cy="100" r="45" fill="#f4dfaa"/><path d="M0 320 Q200 140 400 290 T800 240 V400 H0Z" fill="#47665d"/><path d="M0 360 Q240 260 500 350 T800 310 V400 H0Z" fill="#253d39"/></svg>'

export function toggleIllustration(button) {
  const figure = button.closest('.page-illustration')
  if (toggleScene(figure)) return
  const paused = figure.dataset.paused !== 'true'
  figure.dataset.paused = String(paused)
  button.setAttribute('aria-pressed', String(paused))
  button.textContent = t(paused ? 'Play animation' : 'Pause animation')
}

export const IllustrationCode = hook => CodeBlock.extend({
  addProseMirrorPlugins() {
    return [...(this.parent?.() || []), new Plugin({
      appendTransaction: (_transactions, _previous, state) => {
        const {selection} = state, node = selection.$from.parent
        if (!(selection instanceof TextSelection) || node.type.name !== 'codeBlock' || !languages.has(node.attrs.language)) return null
        const position = selection.$from.before()
        const element = hook.editor?.view.nodeDOM(position)
        if (element?.dataset.svgSourceOpen === 'true') return null
        return state.tr.setSelection(NodeSelection.create(state.doc, position))
      }
    })]
  },
  addNodeView() {
    return ({node, getPos}) => {
      let current = node, version = 0, timer, destroyed = false, sourceVisible = false
      const dom = document.createElement('div'), contentDOM = document.createElement('code')
      const pre = document.createElement('pre'), preview = document.createElement('div')
      const toolbar = document.createElement('div'), edit = document.createElement('button'), refine = document.createElement('button')
      preview.contentEditable = 'false'
      toolbar.className = 'illustration-editor-tools'
      toolbar.contentEditable = 'false'
      edit.type = 'button'
      const editLabel = () => current.attrs.language === 'leitor-figure' ? 'Edit figure' : 'Edit SVG'
      const hideLabel = () => current.attrs.language === 'leitor-figure' ? 'Hide figure source' : 'Hide SVG source'
      edit.textContent = t(editLabel())
      edit.onclick = () => {
        sourceVisible = !sourceVisible
        pre.hidden = !sourceVisible
        dom.dataset.svgSourceOpen = String(sourceVisible)
        edit.textContent = t(sourceVisible ? hideLabel() : editLabel())
        if (!sourceVisible) hook.editor.commands.setNodeSelection(getPos())
      }
      refine.type='button';refine.textContent=t('Adjust with AI')
      refine.onclick=()=>hook.ai?.refine(current.textContent,getPos(),current.nodeSize)
      toolbar.append(refine,edit); pre.append(contentDOM); dom.append(preview, toolbar, pre)
      const update = () => {
        const illustrated = languages.has(current.attrs.language)
        try {refine.hidden=JSON.parse(current.textContent).engine!=='anatomy-program'} catch (_) {refine.hidden=true}
        dom.className = illustrated ? 'illustration-editor' : ''
        preview.hidden = toolbar.hidden = !illustrated
        if (!illustrated) {pre.hidden = false; return}
        pre.hidden = !sourceVisible
        const request = ++version, source = current.textContent, language = current.attrs.language
        clearTimeout(timer)
        timer = setTimeout(() => hook.pushEvent('preview-artwork', {source,language}, ({html}) => {
          if (destroyed || request !== version) return
          destroyScenes(preview)
          preview.innerHTML = html
          mountScenes(preview)
        }), 120)
      }
      update()
      return {
        dom, contentDOM,
        update(next) {
          if (next.type !== current.type) return false
          const changed = next.attrs.language !== current.attrs.language || next.textContent !== current.textContent
          current = next
          if (changed) update()
          return true
        },
        stopEvent: event => Boolean(event.target.closest('.figure-stage, .figure-controls, button')),
        ignoreMutation: mutation => mutation.type !== 'selection' && !contentDOM.contains(mutation.target),
        destroy() {destroyed = true; clearTimeout(timer); destroyScenes(preview)}
      }
    }
  }
})

export function starterScene() {
  const point=(x,y,z)=>`${(220+(x-y)*.866).toFixed(1)},${(125+(x+y)*.5-z).toFixed(1)}`
  const poly=points=>'M'+points.map(p=>point(...p)).join(' L')+'Z'
  const line=(a,b)=>`M${point(...a)}L${point(...b)}`
  const B=140,H=66
  const grid=[35,70,105].map(t=>line([t,0,H],[t,B,H])+line([0,t,H],[B,t,H])).join('')
  const svg=`<svg xmlns="http://www.w3.org/2000/svg" viewBox="30 10 620 340"><title>Conexões que transformam a leitura</title><defs><linearGradient id="topShade" x1="0" y1="0" x2="1" y2="1"><stop stop-color="#f7fbff"/><stop offset="1" stop-color="#e4edf6"/></linearGradient></defs><rect x="30" y="10" width="620" height="340" rx="20" fill="#fcfbf8"/><g fill="none" stroke-linejoin="round" stroke-linecap="round"><path d="${poly([[-12,-12,0],[B+12,-12,0],[B+12,B+12,0],[-12,B+12,0]])}" stroke="#c7cdd5" stroke-dasharray="2 6"/><path d="${poly([[0,B,H],[B,B,H],[B,B,0],[0,B,0]])}" fill="#fffefa" stroke="#9ba5b3" stroke-width="1.4"/><path d="${poly([[B,0,H],[B,B,H],[B,B,0],[B,0,0]])}" fill="#f4f4ef" stroke="#9ba5b3" stroke-width="1.4"/><path d="${poly([[0,0,H],[B,0,H],[B,B,H],[0,B,H]])}" fill="url(#topShade)" stroke="#9ba5b3" stroke-width="1.4"/><path d="${grid}" stroke="#cad3de" stroke-width="1"/><path d="${line([0,B,H-9],[B,B,H-9])+line([B,B,H-9],[B,0,H-9])}" stroke="#d6d9dd"/><path d="${poly([[B,38,47],[B,98,47],[B,98,16],[B,38,16]])}" fill="#e9edf2" stroke="#98a5b7"/><path d="${line([B,57,38],[B,57,27])+line([B,79,38],[B,79,27])}" stroke="#6e7d91" stroke-width="2.6"/><circle id="led" cx="${220+(B-110)*.866}" cy="${125+(B+110)*.5-48}" r="3.3" fill="#65a794" stroke="none"/><path d="M401 248C459 269 472 173 552 187" stroke="#b1bbc8" stroke-width="2"/><path d="M405 255C464 277 478 180 556 194" stroke="#d0d5dc" stroke-width="1.4"/><path id="signal" d="M405 255C464 277 478 180 556 194" stroke="#6e9dbe" stroke-width="2.2"/><g id="plug"><path d="${line([177,57,31],[155,57,31])+line([177,79,31],[155,79,31])}" stroke="#6e7d91" stroke-width="4"/><path d="${poly([[177,42,47],[224,42,47],[224,93,47],[177,93,47]])}" fill="#fffefa" stroke="#9ba5b3" stroke-width="1.3"/><path d="${poly([[177,93,47],[224,93,47],[224,93,12],[177,93,12]])}" fill="#f4f4ef" stroke="#9ba5b3" stroke-width="1.3"/><path d="${poly([[224,42,47],[224,93,47],[224,93,12],[224,42,12]])}" fill="#e8ecf1" stroke="#9ba5b3" stroke-width="1.3"/><path d="${[188,200,212].map(t=>line([t,42,47],[t,93,47])).join('')}" stroke="#c7cfd9" stroke-width="1"/></g></g></svg>`
  return JSON.stringify({svg,animations:[{target:'plug',kind:'translate',axis:'x',from:0,to:-14,duration:3600},{target:'plug',kind:'translate',axis:'y',from:0,to:-8,duration:3600},{target:'led',kind:'opacity',from:.3,to:1,duration:1800,delay:500},{target:'signal',kind:'draw',from:1,to:0,duration:3600,delay:800}]})
}
