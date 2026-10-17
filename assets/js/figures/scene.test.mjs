import {test} from 'node:test'
import assert from 'node:assert/strict'
import {readFileSync} from 'node:fs'
import {compileScene} from './scene_geometry.mjs'

const source=JSON.parse(readFileSync(new URL('../../../test/fixtures/figures/gears.json',import.meta.url)))
test('composition depends on authored solids, not a fixed machine silhouette',()=>{
  const first=compileScene(source)
  const changed=structuredClone(source)
  changed.parts[0].kind='sphere';changed.parts[0].size=[45,1,1]
  changed.parts[4].position=[-120,40,80]
  const second=compileScene(changed)
  assert.notEqual(first.render(0,0).map(p=>p.markup).join(''),second.render(0,0).map(p=>p.markup).join(''))
  assert.equal(first.count,11)
})
test('opening and time reproject real solids while stationary parts remain stable',()=>{
  const renderer=compileScene(source),atRest=renderer.render(0,0),moving=renderer.render(1,1)
  assert.equal(atRest.find(p=>p.key==='0-0').markup,moving.find(p=>p.key==='0-0').markup)
  assert.notEqual(atRest.find(p=>p.key==='4-0').markup,moving.find(p=>p.key==='4-0').markup)
  assert.ok(moving.every(p=>!/(NaN|Infinity)/.test(p.markup)))
  assert.notDeepEqual(renderer.render(0,0,48),renderer.render(0,0,90))
})
