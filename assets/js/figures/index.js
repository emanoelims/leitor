import {buildWorkbench, stationX} from './flow_geometry.mjs'
import {createFlow, enqueue, advance, occupancy} from './flow_model.mjs'
import {translateAlong} from '../../vendor/anatomy/iso-kit.mjs'
import {t} from '../i18n'
import {mountScene} from './scene_player'
import {mountProgram} from './program_player'

const players=new WeakMap()
const engines=new Map([['anatomy-flow@1', mountFlow],['anatomy-scene@1',mountScene],['anatomy-program@1',mountProgram]])

export function mountFigures(root) {
  for(const element of root.querySelectorAll('[data-figure]')) {
    if(players.has(element)) continue
    const blueprint=JSON.parse(element.dataset.figure)
    const mount=engines.get(`${blueprint.engine}@${blueprint.version}`)
    if(mount) players.set(element,mount(element,blueprint))
  }
}
export function destroyFigures(root) {
  for(const element of root.querySelectorAll('[data-figure]')) {players.get(element)?.();players.delete(element)}
}

function mountFlow(element,blueprint) {
  element.dataset.accent=blueprint.accent
  const theme=()=>{element.dataset.theme=['dark','ink'].includes(document.documentElement.dataset.theme)?'dark':'light'}
  const themeObserver=new MutationObserver(theme)
  themeObserver.observe(document.documentElement,{attributes:true,attributeFilter:['data-theme']});theme()
  const drawing=buildWorkbench(blueprint),stage=element.querySelector('.figure-stage'),controls=element.querySelector('.figure-controls')
  stage.innerHTML=drawing.svg
  let model=createFlow(blueprint),speed=1,visible=false,frame=0,last=null,paused=false,readout=''
  const media=matchMedia('(prefers-reduced-motion: reduce)'),poses=new Map()
  paused=media.matches
  const button=(text,action)=>{const b=document.createElement('button');b.type='button';b.textContent=t(text);b.dataset.action=action;return b}
  const add=button('Add item','add'),burst=button('Send a burst','burst'),play=button(paused?'Play animation':'Pause animation','play'),reset=button('Reset','reset'),step=button('Advance one second','step')
  const source=document.createElement('input');source.type='checkbox';source.checked=true
  const sourceLabel=document.createElement('label');sourceLabel.append(source,document.createTextNode(t('Automatic input')))
  const range=document.createElement('input');range.type='range';range.min='.25';range.max='2';range.step='.25';range.value='1';range.setAttribute('aria-label',t('Simulation speed'))
  const speedLabel=document.createElement('label'),speedValue=document.createElement('output');speedValue.textContent='1×';speedLabel.append(document.createTextNode(t('Speed')),range,speedValue)
  const main=document.createElement('div');main.className='figure-actions';main.append(add,burst,play,step,reset)
  const settings=document.createElement('div');settings.className='figure-settings';settings.append(sourceLabel,speedLabel)
  const stationButtons=blueprint.stages.map((s,index)=>{
    const b=button('',`station-${index}`);b.className='figure-station';b.setAttribute('aria-pressed','true')
    const number=document.createElement('span');number.textContent=String(index+1).padStart(2,'0')
    const label=document.createElement('span');label.textContent=s.label
    const seconds=document.createElement('small');seconds.textContent=`${s.seconds}s`
    b.append(number,label,seconds);return b
  })
  const stations=document.createElement('div');stations.className='figure-stations';stations.append(...stationButtons)
  const status=document.createElement('output');status.className='figure-readout';status.setAttribute('aria-live','off')
  const announce=document.createElement('span');announce.className='sr-only';announce.setAttribute('role','status')
  controls.replaceChildren(stations,status,main,settings,announce)
  const heads=blueprint.stages.map((_,i)=>stage.querySelector(`[data-part="head-${i}"]`)),spindles=blueprint.stages.map((_,i)=>stage.querySelector(`[data-part="spindle-${i}"]`)),lamps=[...stage.querySelectorAll('[data-lamp]')],items=[...stage.querySelectorAll('[data-item]')]
  const needle=stage.querySelector('[data-part="needle"]')
  function draw(dt=0) {
    const positions=model.queue.map((item,i)=>({id:item.id,x:-44-i*12,opacity:1}))
    model.stations.forEach((s,i)=>{
      if(s.item) positions.push({id:s.item.id,x:stationX(i),opacity:1})
      const progress=s.item?s.elapsed/s.seconds:0
      const stroke=s.kind==='press'?15*Math.sin(Math.PI*progress)**2:s.kind==='scanner'?4*Math.sin(Math.PI*progress)**2:0
      heads[i].setAttribute('transform',translateAlong(drawing.projection,[0,0,-stroke]))
      heads[i].querySelector('[data-rotor]')?.setAttribute('transform',`rotate(${progress*360})`)
      const [cx,cy]=drawing.centres[i]
      spindles[i].setAttribute('transform',`rotate(${progress*360} ${cx} ${cy})`)
      lamps[i].dataset.state=!s.enabled?'off':s.item?(progress>=1?'waiting':'working'):'ready'
      stationButtons[i].dataset.state=lamps[i].dataset.state
      stationButtons[i].setAttribute('aria-pressed',String(s.enabled))
      stationButtons[i].setAttribute('aria-label',`${s.label}: ${t(s.enabled?'Pause station':'Resume station')}`)
    })
    for(const item of model.delivered) {
      const age=model.time-item.time
      positions.push({id:item.id,x:stationX(model.stations.length-1)+48*Math.min(1,age*2),opacity:Math.min(1,(1-age)*3)})
    }
    const ids=new Set(positions.map(p=>p.id))
    for(const id of poses.keys()) if(!ids.has(id)) poses.delete(id)
    items.forEach((node,i)=>{
      const item=positions[i]
      node.setAttribute('visibility',item?'visible':'hidden')
      if(!item)return
      const previous=poses.get(item.id)??item.x
      const x=media.matches||dt===0?item.x:previous+(item.x-previous)*(1-Math.exp(-dt/.16))
      poses.set(item.id,x);node.setAttribute('transform',translateAlong(drawing.projection,[x,0,0]))
      node.setAttribute('opacity',String(item.opacity))
      node.dataset.itemId=String(item.id)
    })
    needle.setAttribute('transform',`rotate(${-135+270*model.queue.length/model.limit} 17 17)`)
    const next=`${t('Queued')}: ${model.queue.length}/${model.limit} · ${t('Processing')}: ${occupancy(model)} · ${t('Completed')}: ${model.completed} · ${t('Rejected')}: ${model.rejected}`
    if(next!==readout){status.textContent=next;readout=next}
    element.dataset.paused=String(paused)
    element.dataset.completed=String(model.completed);element.dataset.queued=String(model.queue.length);element.dataset.rejected=String(model.rejected)
    play.textContent=t(paused?'Play animation':'Pause animation');play.setAttribute('aria-pressed',String(paused));play.disabled=media.matches
  }
  function tick(now) {
    frame=0
    const dt=last===null?0:Math.min((now-last)/1000,.05);last=now
    advance(model,dt*speed);draw(dt)
    if(visible&&!paused)frame=requestAnimationFrame(tick)
  }
  function start(){last=null;if(visible&&!document.hidden&&!paused&&!frame)frame=requestAnimationFrame(tick)}
  const click=event=>{
    const action=event.target.closest('[data-action]')?.dataset.action
    if(!action)return
    if(action==='add')enqueue(model)
    if(action==='burst')enqueue(model,model.limit+2)
    if(action==='play') {paused=!paused;if(paused){cancelAnimationFrame(frame);frame=0}else start()}
    if(action==='step')advance(model,1)
    if(action==='reset'){model=createFlow(blueprint);model.automatic=source.checked;poses.clear()}
    if(action.startsWith('station-')) {const s=model.stations[Number(action.slice(8))];s.enabled=!s.enabled}
    draw();announce.textContent=readout
  }
  const input=()=>{model.automatic=source.checked;speed=Number(range.value);speedValue.textContent=`${speed}×`}
  const key=event=>{if(event.target!==stage)return;if(event.code==='Space'){event.preventDefault();enqueue(model);draw();announce.textContent=readout}if(event.key==='ArrowRight'){event.preventDefault();advance(model,1);draw()}}
  const reduced=event=>{if(event.matches){paused=true;cancelAnimationFrame(frame);frame=0;draw()}}
  const visibility=()=>{if(document.hidden){cancelAnimationFrame(frame);frame=0;last=null}else start()}
  const observer=new IntersectionObserver(entries=>{visible=entries.at(-1).isIntersecting;if(visible)start();else{cancelAnimationFrame(frame);frame=0;last=null}},{threshold:.05})
  observer.observe(element);controls.addEventListener('click',click);controls.addEventListener('input',input);stage.addEventListener('keydown',key);media.addEventListener('change',reduced);document.addEventListener('visibilitychange',visibility)
  draw()
  return()=>{cancelAnimationFrame(frame);observer.disconnect();themeObserver.disconnect();controls.removeEventListener('click',click);controls.removeEventListener('input',input);stage.removeEventListener('keydown',key);media.removeEventListener('change',reduced);document.removeEventListener('visibilitychange',visibility)}
}

export const starterFigure = () => JSON.stringify({engine:'anatomy-flow',version:1,title:'A oficina das ideias',caption:'Cada peça é uma ideia: rascunhar, revisar e publicar. Pause uma estação para observar a fila. Os tempos são ilustrativos.',accent:'amber',queue_limit:6,arrival_seconds:1.8,stages:[{label:'Rascunhar',kind:'press',seconds:1.4},{label:'Revisar',kind:'scanner',seconds:3.2},{label:'Publicar',kind:'wheel',seconds:1.2}]})
