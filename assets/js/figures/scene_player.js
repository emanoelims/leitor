import {compileScene} from './scene_geometry.mjs'
import {t} from '../i18n'

export function mountScene(element,blueprint) {
  const compiler=compileScene(blueprint),stage=element.querySelector('.figure-stage'),controls=element.querySelector('.figure-controls')
  const namespace='http://www.w3.org/2000/svg',svg=document.createElementNS(namespace,'svg')
  svg.setAttribute('viewBox','0 0 860 520');svg.classList.add('iso-svg');svg.setAttribute('role','group');svg.setAttribute('aria-label',blueprint.title)
  stage.replaceChildren(svg);element.dataset.accent=blueprint.accent;element.classList.add('authored-scene')
  const media=matchMedia('(prefers-reduced-motion: reduce)'),nodes=new Map()
  let time=0,opening=0,target=0,angle=blueprint.azimuth,frame=0,last=null,visible=false,paused=media.matches
  const button=label=>{const el=document.createElement('button');el.type='button';el.textContent=t(label);return el}
  const toggle=button('Open assembly'),play=button(paused?'Play animation':'Pause animation')
  const label=document.createElement('output');label.className='figure-part-name';label.textContent=t('Select a part to inspect it')
  const slider=(title,min,max,step,value)=>{const wrap=document.createElement('label'),input=document.createElement('input');input.type='range';Object.assign(input,{min,max,step,value});input.setAttribute('aria-label',t(title));wrap.append(document.createTextNode(t(title)),input);return {wrap,input}}
  const explode=slider('Open assembly',0,1,.01,0),camera=slider('View angle',0,360,1,angle),speed=slider('Speed',0,2,.1,1)
  const actions=document.createElement('div');actions.className='figure-actions';actions.append(toggle,play)
  const settings=document.createElement('div');settings.className='figure-settings';settings.append(explode.wrap,camera.wrap,speed.wrap)
  controls.replaceChildren(label,actions,settings)
  const theme=()=>{element.dataset.theme=['dark','ink'].includes(document.documentElement.dataset.theme)?'dark':'light'}
  const themeObserver=new MutationObserver(theme);themeObserver.observe(document.documentElement,{attributes:true,attributeFilter:['data-theme']});theme()
  let selected=null
  function draw() {
    const results=compiler.render(opening,time,angle)
    for(const part of results) {
      let entry=nodes.get(part.key)
      if(!entry) {
        const group=document.createElementNS(namespace,'g');group.classList.add('scene-part');group.dataset.partKey=part.key;group.setAttribute('role','button');group.setAttribute('tabindex','0');group.setAttribute('aria-label',part.name)
        entry={group,markup:null};nodes.set(part.key,entry)
      }
      if(entry.markup!==part.markup){entry.group.innerHTML=part.markup;entry.markup=part.markup}
      entry.group.dataset.accent=String(part.accent);entry.group.dataset.selected=String(selected===part.key)
    }
    const order=results.map(p=>p.key).join(',')
    if(svg.dataset.order!==order){for(const p of results)svg.append(nodes.get(p.key).group);svg.dataset.order=order}
    element.dataset.paused=String(paused);element.dataset.opening=opening.toFixed(3)
    play.disabled=media.matches;play.textContent=t(paused?'Play animation':'Pause animation')
    toggle.textContent=t(target>.5?'Close assembly':'Open assembly')
  }
  function tick(now) {
    frame=0;const dt=last===null?0:Math.min((now-last)/1000,.05);last=now
    if(!paused)time+=dt*Number(speed.input.value)
    opening=media.matches?target:opening+(target-opening)*(1-Math.exp(-dt/.18))
    if(Math.abs(target-opening)<.001)opening=target
    draw()
    if(visible&&!document.hidden&&(!paused||opening!==target))frame=requestAnimationFrame(tick)
  }
  function start(){if(!frame&&visible&&!document.hidden){last=null;frame=requestAnimationFrame(tick)}}
  toggle.onclick=()=>{target=target>.5?0:1;explode.input.value=String(target);if(media.matches)opening=target;draw();start()}
  play.onclick=()=>{paused=!paused;draw();start()}
  explode.input.oninput=()=>{target=Number(explode.input.value);if(media.matches)opening=target;draw();start()}
  camera.input.oninput=()=>{angle=Number(camera.input.value);draw()}
  const select=event=>{const part=event.target.closest('[data-part-key]');if(!part)return;selected=part.dataset.partKey;label.textContent=part.getAttribute('aria-label');draw()}
  const key=event=>{if(['Enter',' '].includes(event.key)){event.preventDefault();select(event)}}
  svg.addEventListener('click',select);svg.addEventListener('keydown',key)
  const reduced=event=>{if(event.matches){paused=true;opening=target;draw()}}
  media.addEventListener('change',reduced)
  const visibility=()=>{if(document.hidden){cancelAnimationFrame(frame);frame=0}else start()}
  document.addEventListener('visibilitychange',visibility)
  const observer=new IntersectionObserver(entries=>{visible=entries.at(-1).isIntersecting;if(visible)start();else {cancelAnimationFrame(frame);frame=0}},{threshold:.05});observer.observe(element)
  draw()
  return()=>{cancelAnimationFrame(frame);observer.disconnect();themeObserver.disconnect();media.removeEventListener('change',reduced);document.removeEventListener('visibilitychange',visibility);svg.removeEventListener('click',select);svg.removeEventListener('keydown',key)}
}
