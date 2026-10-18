// Independent probe, executed in the isolated browser, never in the reader.
import * as crankSpecimen from './model.mjs';
function crankInvariant(ok,message){if(!ok)throw Error('Independent crank check: '+message);}
const crankDistance=(a,b)=>Math.hypot(...a.map((v,i)=>v-b[i]));
const crankNear=(a,b)=>Math.abs(a-b)<1e-7;
let crankMin=Infinity,crankMax=-Infinity;
for(let degrees=0;degrees<=360;degrees+=.5){
 const state=crankSpecimen.step(crankSpecimen.initial(),'angle',degrees),before=JSON.stringify(state),p=crankSpecimen.pose(state);
 crankInvariant(crankNear(crankDistance(p.a,[0,0,28]),24),'eccentric radius changes at '+degrees);
 crankInvariant(crankNear(crankDistance(p.a,p.b),80),'rod stretches or joint detaches at '+degrees);
 crankInvariant(crankNear(p.b[1],0)&&crankNear(p.b[2],28),'cursor leaves guide axis');
 crankInvariant(p.x>=56-1e-7&&p.x<=104+1e-7,'cursor exceeds guide travel');
 crankInvariant(crankNear(p.travel,104-p.b[0]),'readout does not describe the drawn pin');
 crankInvariant(crankNear(p.rodAngle,Math.atan2(p.b[1]-p.a[1],p.b[0]-p.a[0])),'rod orientation disagrees with pins');
 crankInvariant(JSON.stringify(state)===before,'pose mutates simulation state');
 crankMin=Math.min(crankMin,p.x);crankMax=Math.max(crankMax,p.x);
}
crankInvariant(crankNear(crankMax-crankMin,48),'stroke is not twice the 24 mm radius');
const crankQuarter=crankSpecimen.pose({angle:90});
crankInvariant(crankQuarter.travel>24&&crankQuarter.travel<28,'quarter turn incorrectly uses sinusoidal slider displacement');
const crankRunning={...crankSpecimen.initial(),playing:true};
crankInvariant(crankNear(crankSpecimen.advance(crankRunning,.05).angle,56.8),'forward animation uses an independent pose');
crankInvariant(crankNear(crankSpecimen.advance({...crankRunning,direction:-1},.05).angle,53.2),'reverse animation does not reverse');
crankInvariant(crankSpecimen.advance({...crankRunning,playing:false},.05).angle===55,'pause drifts');
crankInvariant(crankNear(crankSpecimen.advance(crankRunning,20).angle,56.8),'large frame delta is not bounded');
crankInvariant(crankSpecimen.step(crankRunning,'angle',999).angle===360,'slider upper bound');
crankInvariant(crankSpecimen.step(crankRunning,'angle',-99).angle===0,'slider lower bound');
crankInvariant(JSON.stringify(crankSpecimen.step(crankRunning,'reset'))===JSON.stringify(crankSpecimen.initial()),'reset does not restore canonical state');
