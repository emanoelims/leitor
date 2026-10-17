// Independent constraints, executed only in the disposable browser checker.
import * as bench from './model.mjs'
const check=(ok,why)=>{if(!ok)throw Error('Mechanical bench invariant: '+why)}
const near=(a,b)=>Math.abs(a-b)<1e-8
let low=Infinity,high=-Infinity
for(let i=0;i<=720;i++){
  const state=bench.step(bench.initial(),'angle',i),p=bench.pose(state),[x,y]=p.linkage.pin,[sx,sy]=p.linkage.slider
  check(near(Math.hypot(x,y),8),'crank radius')
  check(near(Math.hypot(sx-x,sy-y),30),'rigid rod and closed joints')
  check(near(sy,0),'slider guide')
  check(near(p.angles[0]*20+(p.angles[1]-Math.PI-Math.PI/40)*40,0),'opposing pitch rotation')
  check(near(p.driven,-i/2),'readout matches gearing')
  check(near(p.linkage.displacement,sx+38),'readout matches slider position')
  low=Math.min(low,p.linkage.displacement);high=Math.max(high,p.linkage.displacement)
}
check(near(low,0)&&near(high,16),'full slider stroke')
const locked=bench.step(bench.initial(),'lock')
check(bench.step(locked,'angle',180)===locked,'lock blocks manual drive')
check(bench.step(locked,'play')===locked,'lock blocks powered drive')
check(bench.advance({...locked,playing:true},.05).angle===locked.angle,'lock blocks animation')
const moving={...bench.initial(),playing:true}
check(near(bench.advance(moving,100).angle,37.5),'bounded frame delta')
check(bench.advance(bench.initial(),.05).angle===36,'pause holds pose')
