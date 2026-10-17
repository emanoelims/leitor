import * as k from '../../vendor/anatomy/iso-kit.mjs'
import * as G from '../../vendor/anatomy/lathe.mjs'

const add=(a,b)=>a.map((n,i)=>n+b[i])
const mul=(a,b)=>a.map(n=>n*b)

// No subject-specific apparatus exists here: the author supplies every solid.
export function compileScene(scene) {
  const records=[]
  scene.parts.forEach((part,index)=>{
    const frame=G.frameAlong(part.position,part.axis)
    if(Math.abs(frame.a[2]-1)<1e-6){frame.u=[1,0,0];frame.v=[0,1,0]}
    for(let copy=0;copy<part.repeat;copy++) {
      const angle=copy/part.repeat*Math.PI*2
      const ring=part.radial>0?add(mul(frame.u,Math.cos(angle)*part.radial),mul(frame.v,Math.sin(angle)*part.radial)):[0,0,0]
      records.push({part,key:`${index}-${copy}`,frame:{...frame,o:add(add(part.position,mul(part.spacing,copy)),ring)},cache:null})
    }
  })
  const bounds=[]
  for(const {part,frame} of records) {
    const [a,b,c]=part.size
    const length=part.kind==='box'?c:['sphere'].includes(part.kind)?0:part.kind==='lathe'?Math.max(...part.profile.map(p=>p[0])):b
    const radius=part.kind==='box'?Math.hypot(a,b)/2:part.kind==='lathe'?Math.max(...part.profile.map(p=>p[1])):a
    const centre=add(frame.o,mul(frame.a,length/2)),r=Math.hypot(radius,length/2)
    for(const opening of [0,1]) for(const dx of [-r,r])for(const dy of [-r,r])for(const dz of [-r,r]) bounds.push(add(add(centre,[dx,dy,dz]),mul(part.explode,opening)))
  }
  const projection = azimuth=>k.fitProjection(bounds,860,520,{pad:28,azimuth,elevation:scene.elevation})
  return {
    count:records.length,
    render(opening,time,azimuth=scene.azimuth) {
      const P=projection(azimuth)
      return records.map(record=>{
        const {part,frame}=record
        const angle=(time*part.spin%360)*Math.PI/180
        const key=`${opening.toFixed(4)}:${angle.toFixed(4)}:${azimuth.toFixed(2)}`
        if(record.cache?.key===key)return record.cache.result
        const F={o:add(frame.o,mul(part.explode,opening)),a:frame.a,u:add(mul(frame.u,Math.cos(angle)),mul(frame.v,Math.sin(angle))),v:add(mul(frame.v,Math.cos(angle)),mul(frame.u,-Math.sin(angle)))}
        const [a,b,c]=part.size
        let paths
        if(part.kind==='box') paths=G.prismOf(F,[[-a/2,-b/2],[a/2,-b/2],[a/2,b/2],[-a/2,b/2]],0,c,P)
        if(part.kind==='cylinder')paths=G.disc(0,b,a,F,P,{steps:36})
        if(part.kind==='ring')paths=G.ringBand(0,b,c,a,F,P,{steps:40})
        if(part.kind==='sphere')paths=G.sphereOf(F.o,a,P,{steps:36})
        if(part.kind==='lathe')paths=G.lathe(part.profile,F,P,{steps:40})
        if(part.kind==='gear') {
          const ring=Array.from({length:64},(_,i)=>{const angle=i/64*Math.PI*2,r=i%4<2?a:a*.82;return [r*Math.cos(angle),r*Math.sin(angle)]})
          paths=G.prismOf(F,ring,0,b,P)
        }
        const result={key:record.key,name:part.name,accent:part.tone==='accent',depth:k.depthOf(add(F.o,mul(F.a,(part.kind==='box'?c:b)/2)),P),markup:k.solidSvg(paths,{tone:part.tone==='accent'?'hi':part.tone})}
        record.cache={key,result};return result
      }).sort((a,b)=>a.depth-b.depth)
    }
  }
}
