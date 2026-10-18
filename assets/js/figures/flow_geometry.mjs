import * as k from '../../vendor/anatomy/iso-kit.mjs'

const escape = value => String(value).replace(/[&<>"']/g, c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]))
export const stationX = index => 22+index*102

// Original Leitor workbench assemblies. Every component shares the kit's camera.
export function buildWorkbench(blueprint) {
  const end=stationX(blueprint.stages.length-1)+92
  const plate={x:-152,y:-66,w:end+166,d:139,r:8}
  const P=k.fitProjection([...k.boxCorners(plate,-19,0),[end,5,106],[-150,-50,80]],900,470,{pad:34,azimuth:57,elevation:28})
  const at=p=>k.iso(p,P)
  const line=(points,tone='lo')=>k.lineSvg(k.pathOf(points.map(at),false),{tone})
  const slab=(x,y,w,d,z,h,tone='mid',r=2)=>k.solidSvg(k.slabOf({x,y,w,d,r},z,h,P,5,0.65),{tone})
  const cylinder=(x,y,r,z,h,tone='mid',lit=false)=>k.solidSvg(k.cylinder(x,y,r,z,h,P,32),{tone,lit})
  const screw=(x,y,z)=>cylinder(x,y,1.65,z,.65,'lo')+line([[x-1,y,z+.7],[x+1,y,z+.7]],'mid')
  let base='',back='',front=''
  const footPoints=k.corners(plate,17).sort((a,b)=>k.depthOf([...a,0],P)-k.depthOf([...b,0],P))
  base+=`<path class="iso-halo" d="${k.haloOf(plate,-18,1,P)}"/>`
  for(const [x,y] of footPoints) base+=cylinder(x,y,6,-19,2)+cylinder(x,y,4.4,-17,5)
  base+=slab(plate.x,plate.y,plate.w,plate.d,-12,12,'mid',8)
  base+=k.lineSvg(k.planOutline(k.insetPlan(plate,4),0,P),{tone:'faint'})
  for(const [x,y] of k.corners(plate,8)) base+=screw(x,y,0)
  const strip={x:-131,y:57,w:end+122,d:5,r:1}
  base+=slab(strip.x,strip.y,strip.w,strip.d,0,.7,'lo',1)
  const ticks=k.topTicks(strip.x+4,strip.x+strip.w-4,5,5,strip.y+.5,.8,[1.8,3.6],P)
  base+=k.lineSvg(ticks.minor,{tone:'faint'})+k.lineSvg(ticks.major,{tone:'lo'})
  // A continuous bed and supported guide rails connect every station.
  base+=slab(-139,-23,end+154,46,0,5,'lo',3)
  for(const y of [-22,19]) {
    base+=slab(-139,y,end+154,3,5,5,'mid',1)
    for(let x=-130;x<end+10;x+=25) base+=screw(x,y+1.5,10)
  }
  for(let x=-130;x<end+6;x+=10) base+=slab(x,-18,4,36,5,3.5,'faint',1)
  for(const x of [-140,end+13]) base+=slab(x,-25,4,50,0,13,'mid',1)
  // Feed magazine, engraved label plate, retention screws and guide walls.
  back+=slab(-136,-18,91,36,9,2,'mid')
  back+=slab(-139,-22,97,3,9,15,'lo')
  front+=slab(-139,20,97,3,9,8,'mid')
  for(const x of [-136,-48]) {back+=screw(x,-20.5,24);front+=screw(x,21.5,17)}
  base+=slab(-132,35,67,13,0,.7,'lo',1)
  base+=k.lineSvg([3,6,9].map((dy,i)=>k.pathOf([at([-128,35+dy,.8]),at([-92-i*6,35+dy,.8])],false)).join(''),{tone:'faint',free:true})
  for(const x of [-129,-69]) base+=screw(x,41,.8)
  const moving=[]
  blueprint.stages.forEach((stage,index)=>{
    const x=stationX(index)
    // Bolted shoes, cylindrical uprights, collars and structural crosshead.
    for(const y of [-31,29]) {
      const assembly=slab(x-13,y-7,26,14,0,4)+cylinder(x,y,5,4,3)+cylinder(x,y,2.8,7,68)+cylinder(x,y,4.5,71,5)+screw(x-8,y,4)+screw(x+8,y,4)
      if(y<0) back+=assembly; else front+=assembly
    }
    back+=slab(x-14,-34,28,67,76,7,'mid',3)
    front+=cylinder(x,0,5,69,7)
    back+=k.lineSvg(k.planOutline({x:x-10,y:-30,w:20,d:59,r:2},83,P),{tone:'faint'})
    back+=screw(x,-28,83)+screw(x,27,83)
    // Top motor, cooling fins, rotating control wheel, wiring down the rear post.
    back+=cylinder(x,-4,9,83,3)+cylinder(x,-4,7,86,13)+cylinder(x,-4,7.8,99,2)
    back+=k.lineSvg(k.knurl(x,-4,7,87,97,28,P),{tone:'lo'})
    back+=line([[x+7,-4,90],[x+17,-4,90],[x+17,-31,90],[x+17,-31,7],[x+5,-31,7]],'lo')
    for(const z of [15,47,73]) back+=slab(x+14,-33,5,4,z,2,'lo',.5)
    base+=slab(x-19,-16,38,32,9,3,'mid')
    for(const [dx,dy] of [[-15,-12],[15,-12],[-15,12],[15,12]]) base+=screw(x+dx,dy,12)
    let head=''
    if(stage.kind==='press') {
      head=cylinder(x,0,3.4,40,44)+cylinder(x,0,5,36,4)+slab(x-11,-12,22,24,32,4,'hi')
      head+=line([[x-8,-12,33],[x-8,12,33]],'faint')
    } else if(stage.kind==='scanner') {
      head=slab(x-9,-13,18,26,37,10,'hi')+slab(x-7,-10,14,20,36,1,'lo')
      for(let y=-7;y<=7;y+=7) head+=cylinder(x,y,2.4,35,1,'blue',true)
      head+=cylinder(x,0,3,47,28)
    } else {
      head=cylinder(x,0,3,39,36)+cylinder(x,0,13,36,3,'hi')+cylinder(x,0,3.5,39,2)
      const spokes=[]
      for(let a=0;a<Math.PI*2;a+=Math.PI/6) spokes.push(`M${4*Math.cos(a)} ${4*Math.sin(a)}L${11*Math.cos(a)} ${11*Math.sin(a)}`)
      head+=`<g transform="${k.topMatrix([x,0],39.2,P)}"><g data-rotor="${index}"><path class="iso-line" data-tone="mid" d="${spokes.join('')}"/></g></g>`
    }
    // Motor spindle and the work head move independently, not the whole drawing.
    moving.push(`<g data-part="head-${index}">${head}</g>`)
    const spinAt=at([x,-4,102])
    const spoke=k.pathOf([[spinAt[0]-5,spinAt[1]],[spinAt[0]+5,spinAt[1]]],false)
    back+=`<g data-part="spindle-${index}">${k.lineSvg(spoke,{tone:'hi'})}</g>`
    const lamp=at([x-8,32,55])
    front+=`<circle class="bench-lamp" data-lamp="${index}" cx="${lamp[0]}" cy="${lamp[1]}" r="2.5"/>`
    // Projected station number on a small face plate; prose labels stay outside.
    front+=slab(x-11,31,22,1,45,17,'lo',1)
    front+=`<text transform="${k.sideMatrix([x-5,32],58,P,'left')}" class="bench-number" font-size="9">0${index+1}</text>`
  })
  // Raised output tray with fence and supports.
  const out=stationX(blueprint.stages.length-1)+42
  base+=slab(out,-18,47,36,9,2,'mid')
  front+=slab(out,19,49,3,9,10,'mid',1)+slab(out+47,-20,3,42,9,16,'mid',1)
  // A real dial on its own pedestal, with bezel, recessed face and tick roots.
  const gx=end-7,gy=47
  front+=slab(gx-14,gy-11,28,22,0,3)+cylinder(gx,gy,4,3,4)+cylinder(gx,gy,2.6,7,35)
  const matrix=k.sideMatrix([gx-17,gy],73,P,'left')
  let dial='<circle cx="17" cy="17" r="18" class="bench-dial-rim"/><circle cx="17" cy="17" r="15" class="bench-dial-face"/>'
  for(let i=0;i<21;i++) {
    const angle=(135+i*13.5)*Math.PI/180
    dial+=`<path d="M${17+Math.cos(angle)*11.5} ${17+Math.sin(angle)*11.5}L${17+Math.cos(angle)*14} ${17+Math.sin(angle)*14}" class="iso-line"/>`
  }
  dial+='<g data-part="needle"><path d="M17 20V4" class="bench-needle"/><circle cx="17" cy="17" r="1.6" class="bench-needle-hub"/></g>'
  front+=`<g transform="${matrix}">${dial}</g>`
  const cart=slab(-7,-10,14,20,13,3,'hi')+slab(-5,-8,10,16,16,.8,'lo',.5)+line([[-3,-4,17],[3,-4,17]],'mid')+line([[-3,0,17],[3,0,17]],'faint')
  const pools=Array.from({length:blueprint.queue_limit+blueprint.stages.length+3},(_,i)=>`<g data-item="${i}" visibility="hidden">${cart}</g>`).join('')
  const svg=k.figureSvg({width:900,height:470,label:blueprint.title,body:base+back+`<g class="bench-items">${pools}</g>`+moving.join('')+front})
  return {svg,projection:P,centres:blueprint.stages.map((_,i)=>at([stationX(i),-4,102]))}
}
