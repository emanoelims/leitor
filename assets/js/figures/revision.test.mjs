import {test} from 'node:test'
import assert from 'node:assert/strict'
import {replacementRange} from './revision.mjs'

test('replacement uses the actual node size and rejects changed figures or prose', () => {
  const node = {type:{name:'codeBlock'},attrs:{language:'leitor-figure'},textContent:JSON.stringify({engine:'anatomy-program',artifact_id:'current'}),nodeSize:120}
  const doc = {content:{size:1000},nodeAt:position => position === 40 ? node : {type:{name:'paragraph'},attrs:{}}}
  assert.deepEqual(replacementRange(doc,40,'current'),{from:40,to:160})
  assert.equal(replacementRange(doc,40,'old'),null)
  assert.equal(replacementRange(doc,41,'current'),null)
  for (const position of [-1,1001,null,2.5]) assert.equal(replacementRange(doc,position,'current'),null)
  node.attrs.language = 'javascript'
  assert.equal(replacementRange(doc,40,'current'),null)
  node.attrs.language = 'leitor-figure';node.textContent = 'invalid json'
  assert.equal(replacementRange(doc,40,'current'),null)
})
