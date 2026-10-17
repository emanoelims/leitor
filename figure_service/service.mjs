import http from 'node:http'
import {timingSafeEqual,randomUUID} from 'node:crypto'
import {mkdir,mkdtemp,writeFile,readFile,lstat,rm} from 'node:fs/promises'
import {tmpdir} from 'node:os'
import {spawn} from 'node:child_process'

const secret=process.env.FIGURE_RUNNER_TOKEN
if(!secret||secret.length<32)throw Error('A runner authentication token is required')
const jobs=new Map()
let busy=false
const respond=(res,status,body)=>{res.writeHead(status,{'content-type':'application/json','cache-control':'no-store'});res.end(JSON.stringify(body))}
const allowed=['figure.mjs','geometry.mjs','model.mjs','checks.mjs','css','experiments','capture_steps','model_checks_required','model_only','motion_required']
function validate(source){
  if(!source||typeof source!=='object'||Array.isArray(source)||Object.keys(source).some(k=>!allowed.includes(k)))throw Error('Invalid source')
  for(const name of ['figure.mjs','geometry.mjs','model.mjs','checks.mjs','css'])if(typeof source[name]!=='string'||Buffer.byteLength(source[name])>60000)throw Error('Invalid module')
  if(!Array.isArray(source.experiments)||source.experiments.length>6||!Array.isArray(source.capture_steps)||source.capture_steps.length>8)throw Error('Invalid experiments')
  return source
}
function command(args,timeout=100000){return new Promise((resolve,reject)=>{
  const child=spawn('docker',args,{stdio:['ignore','pipe','pipe']})
  let bytes=0
  const timer=setTimeout(()=>{child.kill('SIGKILL');reject(Error('Runner deadline exceeded'))},timeout)
  const output=data=>{bytes+=data.length;if(bytes>64000){child.kill('SIGKILL');reject(Error('Runner output limit'))}}
  child.stdout.on('data',output);child.stderr.on('data',output)
  child.on('error',error=>{clearTimeout(timer);reject(error)})
  child.on('exit',code=>{clearTimeout(timer);code===0?resolve():reject(Error('Runner execution failed'))})
})}
async function bounded(path,limit){const stat=await lstat(path);if(!stat.isFile()||stat.size>limit)throw Error('Invalid output');return readFile(path)}
async function run(id,source){
  let directory
  const started=Date.now()
  const name=`figure-${id}`
  try{
    directory=await mkdtemp(`${tmpdir()}/figure-`)
    const input=`${directory}/input`,output=`${directory}/output`
    await mkdir(input);await mkdir(output,{mode:0o777});await (await import('node:fs/promises')).chmod(output,0o777)
    for(const file of ['figure.mjs','geometry.mjs','model.mjs','checks.mjs'])await writeFile(`${input}/${file}`,source[file])
    const request=Object.fromEntries(Object.entries(source).filter(([key])=>!key.endsWith('.mjs')))
    await writeFile(`${input}/request.json`,JSON.stringify(request))
    await command(['run','--rm','--name',name,'--label','leitor.figure=true','--network','none','--read-only','--cap-drop','ALL','--security-opt','no-new-privileges','--pids-limit','256','--memory','2g','--memory-swap','2g','--cpus','2','--shm-size','128m','--tmpfs','/tmp:rw,noexec,nosuid,size=256m','--mount',`type=bind,source=${input},target=/input,readonly`,'--mount',`type=bind,source=${output},target=/output`,'leitor-figure:runtime'])
    const report=JSON.parse(await bounded(`${output}/report.json`,50000))
    const names=['light.png','tested.png','detail.png','interaction.png','dark.png','mobile.png']
    if(typeof report.ok!=='boolean'||!Array.isArray(report.images)||report.images.length>6||new Set(report.images).size!==report.images.length||report.images.some(n=>!names.includes(n)))throw Error('Invalid report')
    const images=[]
    for(const name of report.images)images.push((await bounded(`${output}/${name}`,2000000)).toString('base64'))
    const result={report,images}
    if(report.ok&&!report.model_only){result.bundle=(await bounded(`${output}/bundle.js`,1000000)).toString();result.style=(await bounded(`${output}/style.css`,100000)).toString()}
    jobs.set(id,{status:'complete',result})
    console.log(JSON.stringify({event:'figure_check_complete',id,ok:report.ok,elapsed_ms:Date.now()-started}))
  }catch(error){
    const causes=new Map([['Runner deadline exceeded','deadline'],['Runner execution failed','execution'],['Runner output limit','output_limit']])
    const cause=error.code==='ENOENT'?'runtime_unavailable':causes.get(error.message)||'invalid_output'
    console.error(JSON.stringify({event:'figure_check_failed',id,cause,elapsed_ms:Date.now()-started}))
    jobs.set(id,{status:'failed'})
  }
  finally{
    await command(['rm','-f',name],10000).catch(()=>{})
    if(directory)await rm(directory,{recursive:true,force:true})
    busy=false
    setTimeout(()=>jobs.delete(id),120000).unref()
  }
}
const server=http.createServer(async(req,res)=>{
  if(req.method==='GET'&&req.url==='/health'){
    try{await command(['info','--format','{{.ServerVersion}}'],4000);return respond(res,200,{ok:true})}
    catch(_error){return respond(res,503,{ok:false})}
  }
  const token=Buffer.from(req.headers.authorization||''),expected=Buffer.from(`Bearer ${secret}`)
  if(token.length!==expected.length||!timingSafeEqual(token,expected))return respond(res,401,{error:'unauthorized'})
  if(req.method==='POST'&&req.url==='/checks'){
    if(busy)return respond(res,429,{error:'busy'})
    busy=true
    try{
      let size=0,body=[]
      for await(const chunk of req){size+=chunk.length;if(size>600000)throw Error('Request too large');body.push(chunk)}
      const source=validate(JSON.parse(Buffer.concat(body)))
      const id=randomUUID();jobs.set(id,{status:'running'})
      respond(res,202,{id});void run(id,source)
    }catch(_error){busy=false;respond(res,400,{error:'invalid_request'})}
    return
  }
  if(req.method==='GET'&&/^\/checks\/[a-f0-9-]{36}$/.test(req.url||'')){
    const job=jobs.get(req.url.slice(8))
    if(!job)return respond(res,404,{error:'not_found'})
    return respond(res,job.status==='running'?202:job.status==='complete'?200:503,job.result||{status:job.status})
  }
  respond(res,404,{error:'not_found'})
})
server.requestTimeout=15000;server.headersTimeout=10000
server.listen(Number(process.env.PORT||8081),'::',()=>console.log(`Figure checker ready on ${server.address().port}`))
