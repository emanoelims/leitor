import {test} from 'node:test'
import assert from 'node:assert/strict'
import {inspectSources} from './policy.mjs'

const files=code=>({'figure.mjs':code,'geometry.mjs':'export const cube=1','model.mjs':'export const initial=()=>({angle:0})'})
test('original geometry and pure state are not limited to predefined solids',()=>{
  assert.equal(inspectSources(files("import {initial} from './model.mjs';export function mount(root){root.innerHTML='<svg></svg>';return ()=>root.replaceChildren()}")),true)
  assert.equal(inspectSources(files("const paths={top:'M0,0',fill:'M1,1'};export const cap=paths.top")),true)
  assert.equal(inspectSources(files("const top=50;export const height=top+4")),true)
  assert.equal(inspectSources(files("import {orderSurfaces} from '/leitor/occlusion.mjs';export const order=orderSurfaces")),true)
})
test('network, dynamic evaluation, imports and host capabilities are refused before compilation',()=>{
  for(const code of ["fetch('/secret')","const f=fetch;f('x')","import('node:fs')","import fs from 'node:fs'","document.cookie","document.defaultView.constructor('return 1')()","new Worker('x')","export * from './model.mjs'","process.env","top.location='https://example.com'"])assert.throws(()=>inspectSources(files(code)))
  assert.throws(()=>inspectSources({'../../escape.mjs':'export const x=1'}))
  assert.throws(()=>inspectSources(files("import x from '/leitor/../runtime.mjs'")))
})
test('mechanical checks have the same restricted imports and capabilities as authored modules',()=>{
  assert.equal(inspectSources({...files('export const drawing=1'),'checks.mjs':"import {initial} from './model.mjs';export function verify(){return [{name:'finite angle',passed:Number.isFinite(initial().angle)}]}"}),true)
  assert.throws(()=>inspectSources({...files('export const drawing=1'),'checks.mjs':"fetch('https://example.com')"}))
  assert.throws(()=>inspectSources({...files('export const drawing=1'),'checks.mjs':"import fs from 'node:fs'"}))
})
