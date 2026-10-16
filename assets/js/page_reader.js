import {computePosition, offset, flip, shift, hide, autoUpdate} from "@floating-ui/dom"
import {ReadingPosition} from './reading_position'
let selectionGeometry = null
let selectionVersion = 0
const bytes = text => new TextEncoder().encode(text).length
const blocksOf = root => [...root.querySelectorAll('[data-page-block]')]

// Gloss Reader.jumpToBlock: bring a citation into view and briefly wash its prose.
const jumpTimers = new WeakMap()
const jumpToPageBlock = block => {
  if(!block)return
  const top=block.getBoundingClientRect().top+window.scrollY-innerHeight*.28
  window.scrollTo({top:Math.max(0,top),behavior:matchMedia('(prefers-reduced-motion: reduce)').matches?'instant':'smooth'})
  clearTimeout(jumpTimers.get(block))
  block.classList.remove('is-flash')
  void block.offsetWidth
  block.classList.add('is-flash')
  jumpTimers.set(block,setTimeout(()=>{block.classList.remove('is-flash');jumpTimers.delete(block)},1900))
}

export const PageReader = {
  mounted() {
    this.position = new ReadingPosition(this.el)
    this.marks = JSON.parse(this.el.dataset.marks || '[]')
    this.select = () => {
      if (this.el.closest('.page-focus-mode')) return
      const selection = window.getSelection()
      if (!selection?.rangeCount || selection.isCollapsed) return
      const range = selection.getRangeAt(0)
      const first = range.startContainer.parentElement?.closest('[data-page-block]')
      const last = range.endContainer.parentElement?.closest('[data-page-block]')
      if (!first || !last || !this.el.contains(first) || !this.el.contains(last)) return
      const prefix = (block, node, offset) => {const r = document.createRange(); r.selectNodeContents(block); r.setEnd(node,offset); return bytes(r.toString())}
      const rect = range.getBoundingClientRect()
      selectionGeometry = {rect:{x:rect.x,y:rect.y,width:rect.width,height:rect.height},scrollY:window.scrollY,version:++selectionVersion}
      window.dispatchEvent(new Event('page:selection'))
      this.pushEvent('select',{start_block:Number(first.dataset.pageBlock),end_block:Number(last.dataset.pageBlock),start_offset:prefix(first,range.startContainer,range.startOffset),end_offset:prefix(last,range.endContainer,range.endOffset),selection_version:selectionGeometry.version})
    }
    this.onClick = e => {
      if (this.el.closest('.page-focus-mode') || e.target.closest('a')) return
      const mark = e.target.closest('[data-page-mark]')
      if (!window.getSelection()?.isCollapsed) {e.preventDefault(); return}
      if (mark) {if(mark.dataset.pageMark!=='pending')this.pushEvent('activate-mark', {id:mark.dataset.pageMark}); return}
    }
    this.onKey = e => {
      if (e.defaultPrevented || e.target.closest('input,textarea,select,[contenteditable],#page-selection,[role="dialog"],[role="menu"],[role="listbox"],[role="combobox"]') || document.getElementById('page-selection') || document.getElementById('page-shortcut-dialog') || e.metaKey || e.ctrlKey || e.altKey) return
      if (e.key.toLowerCase() === 'f') {e.preventDefault(); this.pushEvent('reading-option',{key:'focus',value:String(!this.el.closest('.page-focus-mode'))}); return}
      if (e.key === 'Escape' && this.el.closest('.page-focus-mode')) {e.preventDefault(); this.pushEvent('reading-option',{key:'focus',value:'false'}); return}
      if (e.key.toLowerCase() === 'n') {e.preventDefault(); this.pushEvent('notebook',{})}
      if (e.key === '?') {e.preventDefault(); this.pushEvent('shortcuts',{})}
    }
    this.updateFocus=()=>{
      cancelAnimationFrame(this.focusFrame)
      this.focusFrame=requestAnimationFrame(()=>{
        const focused=Boolean(this.el.closest('.page-focus-mode'))
        blocksOf(this.el).forEach(block=>block.toggleAttribute('data-read',focused&&block.getBoundingClientRect().bottom<innerHeight*.2))
      })
    }
    this.focusObserver=new MutationObserver(this.updateFocus)
    this.focusObserver.observe(this.el.closest('main'),{attributes:true,attributeFilter:['class']})
    window.addEventListener('scroll',this.updateFocus,{passive:true})
    window.addEventListener('resize',this.updateFocus)
    this.updateFocus()
    this.el.addEventListener('mouseup',this.select)
    this.el.addEventListener('touchend',this.select)
    this.el.addEventListener('click',this.onClick)
    window.addEventListener('keydown',this.onKey)
    this.handleEvent('page-clear-selection',({version}) => {if(version==null||String(version)===String(selectionGeometry?.version))window.getSelection()?.removeAllRanges()})
    this.handleEvent('page-read-start',() => {this.position.reset(); window.scrollTo({top:0,behavior:'instant'})})
    this.handleEvent('page-pending',mark => {this.pending={...mark,id:'pending',kind:'answer',active:true};this.paint();window.dispatchEvent(new Event('page:annotations'))})
    this.handleEvent('page-marks',({marks}) => {
      const sameAnchors=!this.pending&&marks.length===this.marks.length&&marks.every(mark=>this.marks.some(old=>['id','kind','color','from','to'].every(key=>old[key]===mark[key])))
      this.newIds=new Set(marks.filter(mark=>!this.marks.some(old=>old.id===mark.id)).map(mark=>mark.id))
      this.pending=null;this.marks=marks
      if(sameAnchors){
        // Opening or closing a card must not replace text nodes under a native selection.
        this.el.querySelectorAll('[data-page-marks]').forEach(el=>{
          const matching=marks.filter(mark=>el.dataset.pageMarks.split(' ').includes(mark.id))
          const chosen=matching.find(mark=>mark.active)||matching.findLast(mark=>mark.kind!=='highlight')||matching.at(-1)
          if(chosen)el.dataset.pageMark=chosen.id
          el.classList.toggle('is-active',matching.some(mark=>mark.active));el.classList.remove('is-new')
        })
      } else {window.getSelection()?.removeAllRanges();this.paint()}
      window.dispatchEvent(new Event('page:annotations'))
    })
    this.handleEvent('page-jump',({id}) => {
      this.position.interrupt()
      // LiveView restores navigation scroll on the next frame. Jump after that
      // restoration, using the final font metrics and current annotation nodes.
      const version=this.jumpVersion=(this.jumpVersion||0)+1
      document.fonts.ready.then(()=>{
        if(!this.el.isConnected||version!==this.jumpVersion)return
        cancelAnimationFrame(this.jumpFrame)
        this.jumpFrame=requestAnimationFrame(()=>{
          this.jumpFrame=requestAnimationFrame(()=>{
            if(!this.el.isConnected)return
            const mark=this.marks.find(m=>m.id===id)
            const source=this.el.querySelector(`[data-page-marks~="${id}"]`)
            const block=source?.closest('[data-page-block]')||this.el.querySelector(`[data-page-block="${mark?.block}"]`)
            jumpToPageBlock(block)
          })
        })
      })
    })
    this.paint()
  },
  paint() {
    this.el.querySelectorAll('mark[data-page-mark]').forEach(mark => mark.replaceWith(...mark.childNodes))
    this.el.normalize()
    let base=0
    blocksOf(this.el).forEach(block => {
      const walker = document.createTreeWalker(block,NodeFilter.SHOW_TEXT)
      const nodes=[]; let node
      while ((node=walker.nextNode())) nodes.push(node)
      let position=base
      nodes.forEach(node => {
        const text=node.textContent, length=bytes(text)
        const active=[...this.marks,...(this.pending?[this.pending]:[])].filter(m=>m.from!==null && m.from<position+length && m.to>position)
        if (active.length) {
          let local=0; const segments=[]
          for (const character of text) {
            const at=position+local
            const marks=active.filter(m=>m.from<=at && m.to>at)
            const chosen=marks.find(m=>m.active) || marks.findLast(m=>m.kind!=='highlight') || marks.at(-1)
            const key=marks.map(m=>m.id).join('|')
            if (segments.at(-1)?.key===key) segments.at(-1).text+=character
            else segments.push({key,text:character,mark:chosen,highlight:marks.findLast(m=>m.kind==='highlight'),annotated:marks.some(m=>m.kind!=='highlight'),active:marks.some(m=>m.active),fresh:marks.some(m=>this.newIds?.has(m.id)),ids:marks.map(m=>m.id).join(' ')})
            local+=bytes(character)
          }
          const fragment=document.createDocumentFragment()
          segments.forEach(segment=>{
            if (!segment.mark) fragment.append(document.createTextNode(segment.text))
            else {const mark=document.createElement('mark');mark.dataset.pageMark=segment.mark.id;mark.dataset.pageMarks=segment.ids;mark.className=['page-mark',segment.highlight?`highlight-${segment.highlight.color}`:'',segment.annotated?'page-mark-annotation':'',segment.active?'is-active':'',segment.fresh?'is-new':''].filter(Boolean).join(' ');mark.textContent=segment.text;fragment.append(mark)}
          })
          node.replaceWith(fragment)
        }
        position+=length
      })
      base+=bytes(block.textContent)+2
    })
  },
  destroyed() {this.position.destroy();this.jumpVersion=(this.jumpVersion||0)+1;cancelAnimationFrame(this.jumpFrame);this.focusObserver.disconnect();cancelAnimationFrame(this.focusFrame);window.removeEventListener('scroll',this.updateFocus);window.removeEventListener('resize',this.updateFocus);this.el.removeEventListener('mouseup',this.select);this.el.removeEventListener('touchend',this.select);this.el.removeEventListener('click',this.onClick);window.removeEventListener('keydown',this.onKey)}
}

export const PagePopup = {
  mounted() {
    this.panel=document.getElementById('page-selection')
    const reference={contextElement:document.getElementById('page-reading'),getBoundingClientRect:()=>{
      const r=selectionGeometry?.rect
      return r ? new DOMRect(r.x,r.y+selectionGeometry.scrollY-window.scrollY,r.width,r.height) : document.getElementById('page-reading').getBoundingClientRect()
    }}
    this.syncMore=()=>{
      this.moreCleanup?.();this.moreCleanup=null
      if(!this.more?.open)return
      const summary=this.more.querySelector('summary'), menu=this.more.querySelector('.selection-more-menu')
      menu.style.visibility='hidden'
      this.moreCleanup=autoUpdate(summary,menu,()=>{
        computePosition(summary,menu,{strategy:'fixed',placement:this.panel.dataset.placement?.startsWith('bottom')?'bottom-end':'top-end',middleware:[offset(8),flip({padding:14}),shift({padding:14})]}).then(({x,y})=>{
          if(this.more?.open)Object.assign(menu.style,{left:`${x}px`,top:`${y}px`,visibility:'visible'})
        })
      })
    }
    this.position=()=>{
      const more=this.panel.querySelector('#selection-more')
      if(more!==this.more){this.more?.removeEventListener('toggle',this.syncMore);this.more=more;this.more?.addEventListener('toggle',this.syncMore);this.syncMore()}
      return computePosition(reference,this.panel,{strategy:'fixed',placement:window.matchMedia('(pointer: coarse)').matches?'bottom':'top',middleware:[offset(12),flip({padding:{top:72,left:14,right:14,bottom:14}}),shift({padding:14})]}).then(({x,y,placement})=>{if(this.el.isConnected){const rect=reference.getBoundingClientRect();this.panel.dataset.placement=placement;Object.assign(this.panel.style,{left:`${x}px`,top:`${y}px`});this.panel.style.transformOrigin=placement.startsWith('bottom')?'top center':'bottom center';this.panel.style.setProperty('--arrow-x',`${Math.max(16,Math.min(this.panel.offsetWidth-16,rect.x+rect.width/2-x))}px`)}})
    }
    this.cleanup=autoUpdate(reference,this.panel,this.position)
    this.outside=e=>{if(!this.panel.contains(e.target))this.pushEvent('close-selection',{version:this.panel.dataset.selectionVersion})}
    this.keepSelection=e=>{if(!e.target.closest('input,textarea,select'))e.preventDefault()}
    document.addEventListener('pointerdown',this.outside)
    this.panel.addEventListener('mousedown',this.keepSelection)
    window.addEventListener('page:selection',this.position)
  },
  destroyed(){this.cleanup?.();this.moreCleanup?.();this.more?.removeEventListener('toggle',this.syncMore);document.removeEventListener('pointerdown',this.outside);this.panel.removeEventListener('mousedown',this.keepSelection);window.removeEventListener('page:selection',this.position)}
}

export const PageCitations = {
  mounted(){
    const selector='[data-page-cite-mark],.page-answer a[href^="#page-block-"]'
    this.hide=()=>{
      this.generation=(this.generation||0)+1
      this.cleanup?.();this.cleanup=null
      this.trigger?.removeAttribute('aria-describedby');this.trigger=null
      this.el.hidden=true
    }
    this.show=trigger=>{
      const reader=document.getElementById('page-reading')
      const mark=trigger.dataset.pageCiteMark&&reader?.querySelector(`[data-page-marks~="${trigger.dataset.pageCiteMark}"]`)
      const id=trigger.getAttribute('href')?.slice(1)
      const linked=id&&/^page-block-\d+$/.test(id)?document.getElementById(id):null
      const block=mark?mark.closest('[data-page-block]'):linked&&reader?.contains(linked)?linked:null
      if(!block)return
      this.hide();this.trigger=trigger
      this.el.querySelector('[data-cite-number]').textContent=`¶${Number(block.dataset.pageBlock)+1}`
      this.el.querySelector('[data-cite-text]').textContent=block.textContent
      trigger.setAttribute('aria-describedby',this.el.id)
      this.el.style.visibility='hidden'
      this.el.hidden=false
      const generation=this.generation
      this.cleanup=autoUpdate(trigger,this.el,()=>{
        computePosition(trigger,this.el,{strategy:'fixed',placement:'top',middleware:[offset(8),flip({padding:12}),shift({padding:12}),hide()]}).then(({x,y,placement,middlewareData})=>{
          if(generation!==this.generation || !this.el.isConnected)return
          this.el.style.transformOrigin=placement.startsWith('top')?'bottom center':'top center'
          Object.assign(this.el.style,{left:`${x}px`,top:`${y}px`,visibility:middlewareData.hide?.referenceHidden?'hidden':'visible'})
        })
      },{animationFrame:true})
    }
    this.enter=e=>{const trigger=e.target.closest(selector);if(trigger&&trigger!==this.trigger)this.show(trigger)}
    this.leave=e=>{if(this.trigger?.contains(e.target)&&!this.trigger.contains(e.relatedTarget))this.hide()}
    this.click=e=>{
      const link=e.target.closest('.page-answer a[href^="#page-block-"]')
      if(link){
        const id=link.getAttribute('href').slice(1), block=document.getElementById(id)
        if(block&&document.getElementById('page-reading')?.contains(block)){e.preventDefault();jumpToPageBlock(block)}
      }
      if(this.trigger?.contains(e.target))this.hide()
    }
    this.key=e=>{if(e.key==='Escape')this.hide()}
    document.addEventListener('pointerover',this.enter);document.addEventListener('pointerout',this.leave)
    document.addEventListener('focusin',this.enter);document.addEventListener('focusout',this.leave)
    document.addEventListener('click',this.click);document.addEventListener('keydown',this.key)
    window.addEventListener('page:annotations',this.hide)
  },
  destroyed(){
    this.hide()
    document.removeEventListener('pointerover',this.enter);document.removeEventListener('pointerout',this.leave)
    document.removeEventListener('focusin',this.enter);document.removeEventListener('focusout',this.leave)
    document.removeEventListener('click',this.click);document.removeEventListener('keydown',this.key)
    window.removeEventListener('page:annotations',this.hide)
  }
}

// Ported from Gloss Margin.place: anchor the open card and settle neighbours in both directions.
const placeMarginCards = items => {
  const tops=items.map(item=>item.desired), at=items.findIndex(item=>item.active)
  const gap=(a,b)=>a.mini&&b.mini?4:16
  const forward=from=>{for(let i=Math.max(1,from);i<items.length;i++)tops[i]=Math.max(tops[i],tops[i-1]+items[i-1].height+gap(items[i-1],items[i]))}
  if(at<0){if(tops.length)tops[0]=Math.max(0,tops[0]);forward(1)}
  else {forward(at+1);for(let i=at-1;i>=0;i--)tops[i]=Math.min(tops[i],tops[i+1]-gap(items[i],items[i+1])-items[i].height);if(tops[0]<0){tops[0]=0;forward(1)}}
  return tops
}

// These positions belong to the browser. A LiveView patch must retain the
// previous transform so the next layout glides from it, rather than from zero.
export const preserveMarginPlacement = (from, to) => {
  if(!from.matches('[data-margin-mark]') || !to.matches('[data-margin-mark]'))return
  for(const property of ['transform','visibility','transition']){
    to.style[property]=from.style[property]
  }
  for(const attribute of ['data-margin-placed','data-margin-mini']){
    if(from.hasAttribute(attribute))to.setAttribute(attribute,from.getAttribute(attribute))
  }
}

export const PageMargin = {
  mounted() {
    this.root=null
    this.cards=null
    this.connectors=this.el
    this.reader=null
    this.observed=new Set()
    this.placed=new WeakSet()
    this.layout=()=>{
      const root=this.el.closest('.page-margins'), cards=document.getElementById('page-margin-marks'), reader=document.getElementById('page-reading')
      if(!root || !cards || !reader)return
      if(!root.getClientRects().length){this.connectors.replaceChildren();return}
      // LiveView may move ignored hooks while replacing a conditional parent.
      // Resolve the current stream and source before reading their geometry.
      if(root!==this.root || cards!==this.cards || reader!==this.reader){
        if(this.reader)this.resize.unobserve(this.reader)
        this.root=root;this.cards=cards;this.reader=reader
        this.observer.disconnect();this.observer.observe(cards,{childList:true,subtree:true,characterData:true});this.observer.observe(root,{childList:true})
        this.resize.observe(reader)
      }
      const origin=this.cards.getBoundingClientRect().top+window.scrollY
      const entries=[...this.root.querySelectorAll('[data-margin-mark]')]
      entries.forEach(card=>{if(!this.observed.has(card)){this.resize.observe(card);this.observed.add(card)}})
      for(const card of this.observed){if(!card.isConnected){this.resize.unobserve(card);this.observed.delete(card)}}
      const items=entries.map(card=>{
        const source=this.reader.querySelector(`[data-page-marks~="${card.dataset.marginMark}"]`) || document.getElementById(`page-block-${card.dataset.marginBlock}`)
        const rect=source?.getClientRects()[0]
        return {card,source,desired:rect?rect.top+window.scrollY-origin-6:0,active:card.classList.contains('is-active')}
      }).sort((a,b)=>a.desired-b.desired)
      items.forEach((item,i)=>{
        const near=j=>j>=0&&j<items.length&&Math.abs(items[j].desired-item.desired)<88
        item.mini=!item.active&&item.card.dataset.marginKind!=='note'&&(near(i-1)||near(i+1))
        item.card.toggleAttribute('data-margin-mini',item.mini)
        item.height=item.card.offsetHeight
      })
      if(window.innerWidth<1080){
        items.forEach(({card})=>{card.style.removeProperty('transform');card.style.removeProperty('visibility');card.removeAttribute('data-margin-mini');this.placed.delete(card)})
        this.connectors.replaceChildren();this.leaderKey=null;this.cards.style.minHeight='';return
      }
      const tops=placeMarginCards(items)
      let bottom=0
      items.forEach((item,i)=>{
        const card=item.card, fresh=!this.placed.has(card)
        if(fresh)card.style.transition='none'
        card.style.transform=`translateY(${Math.round(tops[i])}px)`
        card.style.visibility='visible'
        card.setAttribute('data-margin-placed','')
        if(fresh){
          // Commit the initial position before enabling subsequent movement.
          card.getBoundingClientRect()
          card.style.removeProperty('transition')
          this.placed.add(card)
        }
        bottom=Math.max(bottom,tops[i]+item.height)
      })
      this.cards.style.minHeight=`${bottom}px`
      const leads=items.filter(item=>item.source&&(item.active||item.card.dataset.marginMark===this.hovered))
      const width=Math.max(1,this.root.getBoundingClientRect().left-this.reader.getBoundingClientRect().right-20)
      const keys=new Set(), ns='http://www.w3.org/2000/svg'
      let height=bottom
      for(const item of leads){
        const source=item.source.getClientRects()[0], end=tops[items.indexOf(item)]+18, start=source.top+source.height/2-origin+window.scrollY
        const key=`${item.card.dataset.marginMark}:${Math.round(start)}:${Math.round(end)}:${Math.round(width)}`
        keys.add(key);height=Math.max(height,start+8,end+8)
        let group=[...this.connectors.children].find(el=>el.dataset.leaderKey===key)
        if(!group){
          group=document.createElementNS(ns,'g');group.dataset.leaderKey=key;group.dataset.marginLeader=item.card.dataset.marginMark
          const path=document.createElementNS(ns,'path'), dot=document.createElementNS(ns,'circle')
          path.setAttribute('d',`M 3 ${start} C ${width*.5} ${start} ${width*.5} ${end} ${width} ${end}`)
          dot.setAttribute('cx','3');dot.setAttribute('cy',String(start));dot.setAttribute('r','2.5')
          group.append(path,dot);this.connectors.append(group)
        }
        group.setAttribute('opacity',item.active?'1':'.6')
      }
      for(const group of [...this.connectors.children])if(!keys.has(group.dataset.leaderKey))group.remove()
      Object.assign(this.connectors.style,{left:`${-width}px`,width:`${width}px`,height:`${Math.max(1,height)}px`})
      this.connectors.setAttribute('viewBox',`0 0 ${width} ${Math.max(1,height)}`)
    }
    this.schedule=()=>{cancelAnimationFrame(this.frame);this.frame=requestAnimationFrame(this.layout)}
    this.observer=new MutationObserver(this.schedule)
    this.resize=new ResizeObserver(this.schedule)
    this.hover=e=>{
      const target=e.type.endsWith('out')?e.relatedTarget:e.target
      const card=target?.closest?.('[data-margin-mark]'), mark=target?.closest?.('[data-page-marks]')
      const id=card&&this.root?.contains(card)?card.dataset.marginMark:mark&&this.reader?.contains(mark)?mark.dataset.pageMark:null
      if(id===this.hovered)return
      this.hovered=id
      this.root?.querySelectorAll('[data-margin-mark]').forEach(el=>el.classList.toggle('is-hover',el.dataset.marginMark===id))
      this.reader?.querySelectorAll('[data-page-marks]').forEach(el=>el.classList.toggle('is-hover',el.dataset.pageMarks.split(' ').includes(id)))
      this.schedule()
    }
    this.outside=e=>{
      if(e.button!==0 || !this.root?.querySelector('#page-margin-marks .is-active'))return
      // Match Gloss: source marks, other cards and reader tools keep their own actions.
      if(e.target.closest('[data-margin-mark],[data-page-marks],#page-selection,header,#page-notebook-panel,[role="dialog"],.page-cite'))return
      this.pushEvent('collapse-mark',{})
    }
    document.addEventListener('pointerdown',this.outside)
    document.addEventListener('pointerover',this.hover);document.addEventListener('pointerout',this.hover)
    document.addEventListener('focusin',this.hover);document.addEventListener('focusout',this.hover)
    window.addEventListener('resize',this.schedule);window.addEventListener('page:annotations',this.schedule)
    document.fonts.ready.then(this.schedule);this.schedule()
  },
  updated(){this.schedule()},
  destroyed(){this.observer.disconnect();this.resize.disconnect();cancelAnimationFrame(this.frame);document.removeEventListener('pointerover',this.hover);document.removeEventListener('pointerout',this.hover);document.removeEventListener('focusin',this.hover);document.removeEventListener('focusout',this.hover);document.removeEventListener('pointerdown',this.outside);window.removeEventListener('resize',this.schedule);window.removeEventListener('page:annotations',this.schedule)}
}

export const PageRail = {
  mounted() {
    this.reader=document.getElementById('page-reading')
    this.bars=this.el.querySelector('.page-rail-bars')
    this.thumb=this.el.querySelector('.page-rail-viewport')
    this.markers=this.el.querySelector('.page-rail-markers')
    this.measure=()=>{
      const rect=this.reader.getBoundingClientRect(), railHeight=this.el.clientHeight
      if(!railHeight)return
      this.top=rect.top+window.scrollY;this.height=Math.max(1,rect.height)
      const scale=railHeight/this.height
      this.bars.replaceChildren();this.markers.replaceChildren()
      blocksOf(this.reader).forEach(block=>{
        const bar=document.createElement('span'),r=block.getBoundingClientRect(),heading=Boolean(block.querySelector('h1,h2,h3'))
        bar.style.top=`${(r.top-rect.top)*scale}px`
        bar.style.height=`${Math.max(1,r.height*scale-2)}px`
        bar.style.width=`${heading?100:Math.min(1,.45+block.textContent.length/1400)*100}%`
        bar.className=heading?'rail-heading':'';this.bars.append(bar)
      })
      const dots=[], size=parseFloat(getComputedStyle(this.el).getPropertyValue('--rail-dot-size'))||5
      const marks=JSON.parse(this.reader.dataset.marks||'[]')
      for(const mark of marks){
        const source=this.reader.querySelector(`[data-page-marks~="${mark.id}"]`),r=source?.getClientRects()[0]
        if(!r)continue
        const y=Math.max(0,Math.min(railHeight-size,(r.top+r.height/2-rect.top)*scale))
        const marker=document.createElement('span')
        marker.dataset.railMark=mark.id;marker.title=`¶${Number(source.closest('[data-page-block]').dataset.pageBlock)+1} · ${mark.kind}`
        marker.className=mark.kind==='highlight'?'page-rail-highlight':'page-rail-dot'
        marker.dataset.color=mark.color
        marker.style.top=`${y}px`
        if(mark.kind==='highlight')this.markers.append(marker)
        else dots.push({marker,y})
      }
      // Keep nearby annotations separate, including several on the same line.
      dots.sort((a,b)=>a.y-b.y)
      const gap=Math.min(7,(railHeight-size)/Math.max(1,dots.length-1))
      const tops=dots.map(dot=>dot.y)
      for(let i=1;i<tops.length;i++)tops[i]=Math.max(tops[i],tops[i-1]+gap)
      if(tops.length&&tops.at(-1)>railHeight-size){
        tops[tops.length-1]=railHeight-size
        for(let i=tops.length-2;i>=0;i--)tops[i]=Math.min(tops[i],tops[i+1]-gap)
      }
      dots.forEach((dot,i)=>{dot.marker.style.top=`${tops[i]}px`;this.markers.append(dot.marker)})
      this.update()
    }
    this.update=()=>{
      if(!this.el.clientHeight)return
      const fraction=this.height<=innerHeight?1:Math.max(0,Math.min(1,(window.scrollY-this.top)/(this.height-innerHeight)))
      this.el.setAttribute('aria-valuenow',String(Math.round(fraction*100)))
      const start=Math.max(0,Math.min(this.height,scrollY-this.top)),end=Math.max(0,Math.min(this.height,scrollY+innerHeight-this.top))
      const top=start/this.height*this.el.clientHeight
      this.thumb.hidden=end<=start
      this.thumb.style.top=`${top}px`
      this.thumb.style.height=`${Math.min(this.el.clientHeight-top,Math.max(14,(end-start)/this.height*this.el.clientHeight))}px`
    }
    this.travel=e=>{const r=this.el.getBoundingClientRect();const fraction=Math.max(0,Math.min(1,(e.clientY-r.top)/r.height));window.scrollTo({top:this.top+fraction*this.height-innerHeight*.3,behavior:'instant'})}
    this.down=e=>{this.dragging=true;this.el.setPointerCapture(e.pointerId);this.travel(e)}
    this.move=e=>{if(this.dragging)this.travel(e)};this.up=()=>{this.dragging=false}
    this.key=e=>{if(['ArrowDown','ArrowUp','Home','End'].includes(e.key)){e.preventDefault();window.scrollTo({top:e.key==='Home'?0:e.key==='End'?document.documentElement.scrollHeight:window.scrollY+(e.key==='ArrowDown'?1:-1)*innerHeight*.7,behavior:'smooth'})}}
    this.resize=new ResizeObserver(this.measure);this.resize.observe(this.reader);this.resize.observe(this.el)
    this.el.addEventListener('pointerdown',this.down);this.el.addEventListener('pointermove',this.move);this.el.addEventListener('pointerup',this.up);this.el.addEventListener('pointercancel',this.up);this.el.addEventListener('keydown',this.key)
    window.addEventListener('scroll',this.update,{passive:true});window.addEventListener('resize',this.measure);window.addEventListener('page:annotations',this.measure)
    document.fonts.ready.then(this.measure);this.measure()
  },
  destroyed(){this.resize.disconnect();this.el.removeEventListener('pointerdown',this.down);this.el.removeEventListener('pointermove',this.move);this.el.removeEventListener('pointerup',this.up);this.el.removeEventListener('pointercancel',this.up);this.el.removeEventListener('keydown',this.key);window.removeEventListener('scroll',this.update);window.removeEventListener('resize',this.measure);window.removeEventListener('page:annotations',this.measure)}
}
