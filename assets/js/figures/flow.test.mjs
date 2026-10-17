import {test} from 'node:test'
import assert from 'node:assert/strict'
import {readFileSync} from 'node:fs'
import {createFlow,enqueue,advance,occupancy} from './flow_model.mjs'
import {buildWorkbench} from './flow_geometry.mjs'

const blueprint=JSON.parse(readFileSync(new URL('../../../test/fixtures/figures/workbench.json',import.meta.url),'utf8'))
test('a disabled station holds work, queues back up, and rejected arrivals are never counted as completed',()=>{
  const model=createFlow(blueprint);model.automatic=false;model.stations[1].enabled=false
  enqueue(model,10);assert.equal(model.rejected,4)
  advance(model,10)
  assert.equal(model.completed,0);assert.equal(model.queue.length,4);assert.equal(occupancy(model),2)
  model.stations[1].enabled=true
  for(let i=0;i<6;i++)advance(model,10)
  assert.equal(model.completed,6);assert.equal(model.queue.length,0);assert.equal(occupancy(model),0)
})
test('state is conserved, stepping is deterministic, and simulation speed does not depend on rendering',()=>{
  const a=createFlow(blueprint),b=createFlow(blueprint)
  for(let i=0;i<1200;i++)advance(a,1/120)
  for(let i=0;i<100;i++)advance(b,.1)
  assert.equal(a.completed,b.completed);assert.equal(a.accepted,b.accepted)
  assert.equal(a.accepted,a.completed+a.queue.length+occupancy(a))
  assert.ok(a.queue.length<=a.limit)
})
test('the original workbench uses detailed solid geometry in a shared camera and builds identically',()=>{
  const a=buildWorkbench(blueprint),b=buildWorkbench(blueprint)
  assert.equal(a.svg,b.svg);assert.ok((a.svg.match(/iso-solid/g)||[]).length>100)
  assert.ok((a.svg.match(/<path/g)||[]).length>700)
  assert.ok(!a.svg.includes('NaN'));assert.ok(!a.svg.includes('Infinity'))
  assert.ok(a.svg.includes('data-part="head-1"'));assert.ok(a.svg.includes('data-part="needle"'))
})
