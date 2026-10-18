import {t} from './i18n'
import {mountFigures, destroyFigures} from './figures/index'
const players = new WeakMap()

export function mountScenes(root) {
  mountFigures(root)
  for (const figure of root.querySelectorAll('[data-scene]')) {
    if (players.has(figure)) continue
    const animations=[]
    for (const motion of JSON.parse(figure.dataset.scene)) {
      const target=figure.querySelector(`[id="${motion.target}"]`)
      if (!target) continue
      let frames
      const from=motion.from,to=motion.to
      if (motion.kind==='translate') frames=[{transform:`translate${motion.axis.toUpperCase()}(${from}px)`},{transform:`translate${motion.axis.toUpperCase()}(${to}px)`}]
      if (motion.kind==='rotate') frames=[{transform:`rotate(${from}deg)`},{transform:`rotate(${to}deg)`}]
      if (motion.kind==='scale') frames=[{transform:`scale(${from})`},{transform:`scale(${to})`}]
      if (motion.kind==='opacity') frames=[{opacity:from},{opacity:to}]
      if (motion.kind==='draw' && target.getTotalLength) {
        const length=target.getTotalLength()
        target.style.strokeDasharray=String(length)
        frames=[{strokeDashoffset:String(from*length)},{strokeDashoffset:String(to*length)}]
      }
      if (!frames) continue
      target.style.transformBox='fill-box'; target.style.transformOrigin='center'
      animations.push(target.animate(frames,{duration:motion.duration,delay:motion.delay,easing:motion.easing,direction:motion.direction,iterations:Infinity,fill:'both',composite:['translate','rotate','scale'].includes(motion.kind)?'add':'replace'}))
    }
    const media=matchMedia('(prefers-reduced-motion: reduce)')
    const paused=media.matches || figure.dataset.paused==='true'
    if (paused) animations.forEach(animation=>animation.pause())
    const reduce=event=>{if(event.matches){animations.forEach(animation=>animation.pause());setState(figure,true)}}
    media.addEventListener('change',reduce)
    players.set(figure,{animations,media,reduce})
    setState(figure,paused)
  }
}
export function destroyScenes(root) {
  destroyFigures(root)
  for (const figure of root.querySelectorAll('[data-scene]')) {
    const player=players.get(figure)
    player?.animations.forEach(animation=>animation.cancel())
    player?.media.removeEventListener('change',player.reduce)
    players.delete(figure)
  }
}
function setState(figure,paused) {
  figure.dataset.paused=String(paused)
  const button=figure.querySelector('[data-illustration-toggle]')
  if (button) {button.setAttribute('aria-pressed',String(paused));button.textContent=t(paused?'Play animation':'Pause animation')}
}
export function toggleScene(figure) {
  const player=players.get(figure)
  if (!player) return false
  const {animations}=player
  const paused=figure.dataset.paused!=='true'
  animations.forEach(animation=>paused?animation.pause():animation.play())
  setState(figure,paused)
  return true
}
