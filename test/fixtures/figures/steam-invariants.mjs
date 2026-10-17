import * as specimen from './model.mjs';
const verify=(ok,why)=>{if(!ok)throw Error('Independent steam-mill constraint: '+why)};
const close=(a,b)=>Math.abs(a-b)<1e-7;
const distance=(a,b)=>Math.hypot(...a.map((v,i)=>v-b[i]));
const D=specimen.DIM,R=specimen.ROUTE;
for(let i=0;i<=720;i++){
 const p=specimen.pose({...specimen.init(),angle:i*Math.PI/360});
 verify(close(distance(p.pin,[D.crank.x,D.cylY,D.crank.z]),7),'eccentric radius');
 verify(close(distance(p.pin,p.cross),24),'rigid rod/pins');
 verify(close(p.cross[1],D.cylY)&&close(p.cross[2],20),'crosshead guide');
 verify(close(p.cross[0]-p.piston,26),'piston-rod extension');
 verify(p.piston-3>D.cyl.x0&&p.piston+3<D.cyl.x1,'solid piston stays inside bore');
 verify(p.cross[0]-3.8>D.cyl.x1+3,'crosshead does not enter gland');
 verify(close((p.wheelA-Math.PI-Math.PI/104)*104+p.pinionA*20,0),'gear phase ratio');
}
verify(close(Math.hypot(D.top.x-D.crank.x,D.top.z-D.crank.z),31),'pitch centre distance');
for(let i=0;i<=2000;i++){
 const d=R.length*i/2000,p=specimen.routePoint(d),r=specimen.routeRadius(d);
 verify(close(p[1],22),'material remains in roller working plane');
 for(const c of [D.top,D.left,D.right])verify(Math.hypot(p[0]-c.x,p[2]-c.z)-D.rollR>=r-.0001,'material intersects roller at '+d);
}
for(const d of [R.entryLength,R.entryLength+R.bendLength,R.entryLength+R.bendLength+R.deliveryLength]){
 const a=specimen.routePoint(d-.0001),b=specimen.routePoint(d),c=specimen.routePoint(d+.0001);
 verify(distance(a,b)<.000101&&distance(c,b)<.000101,'route positional continuity');
 const u=b.map((x,i)=>x-a[i]),v=c.map((x,i)=>x-b[i]);
 verify(u.reduce((sum,x,i)=>sum+x*v[i],0)/(Math.hypot(...u)*Math.hypot(...v))>.99999,'route tangent continuity');
}
// The thin curved transfer plate remains outside every roller, including
// its underside; it supports fibre without occupying either nip.
for(let i=0;i<=400;i++){
 const a=Math.atan2(-8,5)-.12+(Math.atan2(-8,-5)+.12-(Math.atan2(-8,5)-.12))*i/400;
 const radius=R.radius+.57,x=D.top.x+radius*Math.cos(a),z=D.top.z+radius*Math.sin(a);
 for(const c of [D.top,D.left,D.right])verify(Math.hypot(x-c.x,z-c.z)>D.rollR,'transfer plate intersects a roller');
}
// A supported gravity discharge must stay above the collector and descend
// monotonically after leaving the delivery-roll arc.
const dischargeStart=R.entryLength+R.bendLength+R.deliveryLength;
let previousHeight=specimen.routePoint(dischargeStart)[2];
for(let i=1;i<=100;i++){
 const point=specimen.routePoint(dischargeStart+R.exitLength*i/100);
 verify(point[2]<previousHeight,'discharge chute must slope downward');
 verify(point[2]>8,'discharge stays above the foundation and collection platform');
 previousHeight=point[2];
}
const nipA=specimen.routePoint(R.entryLength),nipB=specimen.routePoint(R.entryLength+R.bendLength);
verify(close(nipA[0],(D.top.x+D.right.x)/2)&&close(nipA[2],(D.top.z+D.right.z)/2),'first nip matches drawn roller centres');
verify(close(nipB[0],(D.top.x+D.left.x)/2)&&close(nipB[2],(D.top.z+D.left.z)/2),'second nip matches drawn roller centres');
let state=specimen.init();verify(specimen.toggleValve(state).msg.includes('Blocked'),'cold start blocked');
verify(specimen.feed(state).queue===0,'stopped feed blocked');
state=specimen.step(specimen.setFire(state,100),20);state=specimen.toggleValve(state);state=specimen.step(state,10);state=specimen.feed(state);state=specimen.step(state,10);
verify(close(state.crushed,1)&&close(state.caneIn,0),'one feed completes one stalk');
