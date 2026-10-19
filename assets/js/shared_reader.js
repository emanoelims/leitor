export const SharedReader = {
  mounted() {
    const key=`leitor:shared-drafts:${this.el.dataset.draftKey}`
    const load=()=>{try{const value=JSON.parse(sessionStorage.getItem(key)||'[]');return Array.isArray(value)?value.slice(0,100):[]}catch{return []}}
    const drafts=load()
    if(drafts.length) this.pushEvent(this.el.dataset.guest==='true'?'restore-guest-drafts':'guest-drafts-found',{drafts})
    this.handleEvent('shared-request-drafts',()=>this.pushEvent('import-guest-drafts',{drafts:load()}))
    this.handleEvent('shared-drafts',({drafts})=>{try{sessionStorage.setItem(key,JSON.stringify(drafts))}catch{}})
    this.handleEvent('shared-comment-focus',()=>requestAnimationFrame(()=>document.getElementById('shared-comment-body')?.focus()))
    this.handleEvent('shared-jump',({block})=>{
      const node=document.getElementById(`page-block-${block}`)
      if(node){node.scrollIntoView({behavior:matchMedia('(prefers-reduced-motion: reduce)').matches?'instant':'smooth',block:'center'});node.classList.remove('is-flash');void node.offsetWidth;node.classList.add('is-flash')}
    })
  }
}
