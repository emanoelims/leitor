import {test} from 'node:test'
import assert from 'node:assert/strict'
import {spawn} from 'node:child_process'
import {once} from 'node:events'

test('private checker authenticates, bounds input and fails closed without an isolated runtime',async t=>{
  const token='test-only-private-checker-token-32-bytes'
  // Empty PATH deliberately makes Docker unavailable. Authored code cannot run
  // in the service process, even when a valid request reaches execution.
  const service=spawn(process.execPath,[new URL('./service.mjs',import.meta.url).pathname],{
    env:{...process.env,FIGURE_RUNNER_TOKEN:token,PORT:'0',PATH:'/unavailable'},stdio:['ignore','pipe','pipe']
  })
  t.after(async()=>{service.kill();await once(service,'exit')})
  const [ready]=await once(service.stdout,'data')
  const port=ready.toString().match(/ready on (\d+)/)?.[1]
  assert.ok(port)
  const base=`http://127.0.0.1:${port}`
  const auth={authorization:`Bearer ${token}`,'content-type':'application/json'}
  assert.equal((await fetch(base+'/health')).status,503)
  assert.equal((await fetch(base+'/checks',{method:'POST',body:'{}'})).status,401)
  assert.equal((await fetch(base+'/checks',{headers:{authorization:'Bearer é'}})).status,401)
  const post=source=>fetch(base+'/checks',{method:'POST',headers:auth,body:JSON.stringify(source)})
  const source={'figure.mjs':'export const figure=1','geometry.mjs':'export const shape=1','model.mjs':'export const state=1','checks.mjs':'export function verify(){return []}',css:'',experiments:[],capture_steps:[]}
  for(const bad of [{...source,'../escape.mjs':'x'},{...source,experiments:Array(7).fill({})},{...source,'model.mjs':'x'.repeat(60001)},[]])assert.equal((await post(bad)).status,400)
  assert.equal((await fetch(base+'/checks',{method:'POST',headers:auth,body:'x'.repeat(600001)})).status,400)
  const response=await post(source)
  assert.equal(response.status,202)
  const {id}=await response.json()
  assert.match(id,/^[a-f0-9-]{36}$/)
  assert.equal((await fetch(base+'/checks/'+id)).status,401)
  let result
  for(let attempt=0;attempt<50;attempt++){
    result=await fetch(base+'/checks/'+id,{headers:auth})
    if(result.status!==202)break
    await result.body.cancel()
    await new Promise(resolve=>setTimeout(resolve,10))
  }
  assert.equal(result.status,503)
  assert.deepEqual(await result.json(),{status:'failed'})
  assert.equal((await fetch(base+'/checks/00000000-0000-0000-0000-000000000000',{headers:auth})).status,404)
})
