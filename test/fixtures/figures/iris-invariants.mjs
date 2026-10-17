// Independent geometric checks; executed only inside the networkless browser runner.
import * as specimen from './model.mjs';
const cross=(a,b)=>a[0]*b[1]-a[1]*b[0];
const sub=(a,b)=>[a[0]-b[0],a[1]-b[1]];
const distance=(a,b)=>Math.hypot(...sub(a,b));
const distance3=(a,b)=>Math.hypot(...a.map((v,i)=>v-b[i]));
function requireInvariant(ok,message){if(!ok)throw Error('Independent iris check: '+message);}
function pointInside(poly,point=[0,0]){poly=poly.map(p=>sub(p,point));let inside=false;for(let i=0,j=poly.length-1;i<poly.length;j=i++){const a=poly[i],b=poly[j];if((a[1]>0)!==(b[1]>0)&&0<(b[0]-a[0])*(-a[1])/(b[1]-a[1])+a[0])inside=!inside;}return inside;}
function opening(pose){
 const radii=[];
 for(let i=0;i<720;i++){
  const a=i*2*Math.PI/720,d=[Math.cos(a),Math.sin(a)];let nearest=Infinity;
  for(const b of pose.blades){const p=b.outline;for(let j=0;j<p.length;j++){
   const q=p[j],s=sub(p[(j+1)%p.length],q),den=cross(d,s);if(Math.abs(den)<1e-9)continue;
   const t=cross(q,s)/den,u=cross(q,d)/den;if(t>0&&u>=0&&u<=1)nearest=Math.min(nearest,t);
  }}
  requireInvariant(Number.isFinite(nearest),'an uncovered radial gap at '+i);radii.push(nearest);
 }
 return {radius:Math.min(...radii),area:radii.reduce((a,r)=>a+r*r,0)*Math.PI/720};
}
const targets=[2.5,2.8,5.6,11,16,22];let previousArea=Infinity;let baseline;
for(const N of targets){
 const psi=specimen.psiFromN(N),pose=specimen.pose({psi}),values=specimen.readout(psi),actual=opening(pose);
 requireInvariant(pose.blades.length===9,'nine blades');
 requireInvariant(pose.blades.every(b=>!pointInside(b.outline)),'a blade covers the optical axis at f/'+N);
 requireInvariant(Math.abs(actual.radius-values.D/2)<.06,'drawn aperture disagrees with diameter at f/'+N+': '+JSON.stringify({actual,values}));
 requireInvariant(actual.area<previousArea,'light area must decrease with f-number');previousArea=actual.area;
 requireInvariant(Math.abs(actual.area-values.area)/actual.area<.05,'area differs from the real opening at f/'+N+': '+JSON.stringify({actual,values}));
 if(!baseline)baseline=pose;
 for(let i=0;i<pose.blades.length;i++){
  const b=pose.blades[i],ref=baseline.blades[i];
  requireInvariant(distance(b.pivot,ref.pivot)<1e-8,'fixed pivot drift');
  requireInvariant(pointInside(b.outline,b.pivot),'pivot is outside its blade');
  requireInvariant(pointInside(b.outline,b.pin),'follower is outside its blade');
  requireInvariant(b.outline.every(p=>Math.hypot(...p)<27.62),'blade collides with the outer ring');
  requireInvariant(Math.abs(distance(b.pin,b.pivot)-distance(ref.pin,ref.pivot))<1e-8,'follower detaches from blade');
  for(let j=0;j<b.surface.length;j++)requireInvariant(Math.abs(distance3(b.surface[j],b.surface[0])-distance3(ref.surface[j],ref.surface[0]))<1e-7,'3D leaf deforms');
  for(let j=0;j<b.outline.length;j++)requireInvariant(Math.abs(distance(b.outline[j],b.pivot)-distance(ref.outline[j],ref.pivot))<1e-7,'blade deforms');
  const slotAngle=Math.atan2(b.pin[1],b.pin[0])-pose.alpha;
  const refAngle=Math.atan2(ref.pin[1],ref.pin[0])-baseline.alpha;
  requireInvariant(Math.abs(Math.sin(slotAngle-refAngle))<1e-8,'follower leaves radial cam slot');
 }
}

requireInvariant(Math.abs(specimen.readout(specimen.psiFromN(5.6)).flux-25)<.01,'doubling f-number must quarter the reference flux');
