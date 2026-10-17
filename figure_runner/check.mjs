import {readFile,writeFile} from 'node:fs/promises'
import {build} from 'esbuild'
import {chromium} from 'playwright-core'
import {inspectSources} from './policy.mjs'

const output='/output'
let browser,page
const report={ok:false,checks:[],errors:[],images:[],network:[],drawing_changes:0,toolchain:{node:process.version,kit:'e9488296a44211c42701ff71705b7901470ec78f',facets:'aeea92c80b0d14567de50ea67debf67068663180'}}
async function perform(page,step) {
  const locator=page.locator(step.selector)
  if(step.action==='click')await locator.click()
  else if(step.action==='fill'){await locator.fill(step.value);await locator.dispatchEvent('input')}
  else if(step.action==='press')await locator.press(step.value)
  else if(step.action==='range')await locator.evaluate((element,value)=>{element.value=value;element.dispatchEvent(new Event('input',{bubbles:true}));element.dispatchEvent(new Event('change',{bubbles:true}))},step.value)
  else throw Error('Unknown experiment action')
}
async function captureState(page) {
  return page.locator('#figure-root').evaluate(root=>({
    classes:root.className.slice(0,300),
    viewBox:root.querySelector('svg')?.getAttribute('viewBox')?.slice(0,300),
    toggles:[...root.querySelectorAll('button[aria-pressed]')].slice(0,24).map(el=>({id:el.id.slice(0,100),text:el.textContent.slice(0,100),pressed:el.getAttribute('aria-pressed')})),
    outputs:[...root.querySelectorAll('output')].slice(0,24).map(el=>({id:el.id.slice(0,100),text:el.textContent.slice(0,100)}))
  }))
}
async function ready(page){
  await page.waitForSelector('html[data-ready="true"],html[data-error]',{state:'attached'})
  const failure=await page.locator('html').getAttribute('data-error')
  if(failure)throw Error(failure)
}
async function mobileFraming(page) {
  return page.locator('#figure-root svg').evaluateAll(nodes=>{
    const visible=nodes.filter(svg=>!svg.ownerSVGElement&&svg.getBoundingClientRect().width&&svg.getBoundingClientRect().height)
    visible.sort((a,b)=>{const x=a.getBoundingClientRect(),y=b.getBoundingClientRect();return y.width*y.height-x.width*x.height})
    const svg=visible[0]
    if(!svg)return {clipped:false}
    const v=svg.viewBox.baseVal,b=svg.getBBox()
    if(!v.width||!v.height||!b.width||!b.height)return {clipped:false}
    const outside={left:Math.max(0,v.x-b.x),right:Math.max(0,b.x+b.width-v.x-v.width),top:Math.max(0,v.y-b.y),bottom:Math.max(0,b.y+b.height-v.y-v.height)}
    const clipped=outside.left>Math.max(4,v.width*.05)||outside.right>Math.max(4,v.width*.05)||outside.top>Math.max(4,v.height*.05)||outside.bottom>Math.max(4,v.height*.05)
    const rounded=object=>Object.fromEntries(Object.entries(object).map(([k,n])=>[k,Math.round(n*10)/10]))
    return {clipped,viewBox:{x:v.x,y:v.y,width:v.width,height:v.height},drawing:rounded({x:b.x,y:b.y,width:b.width,height:b.height}),outside:rounded(outside)}
  })
}
try {
  const request=JSON.parse(await readFile('/input/request.json','utf8'))
  const files={}
  for(const name of ['figure.mjs','geometry.mjs','model.mjs','checks.mjs'])files[name]=await readFile(`/input/${name}`,'utf8')
  inspectSources(files)
  const notices=await readFile('/runner/kit/LICENSE','utf8')+'\n'+await readFile('/runner/kit/COMMUNITY-LICENSE','utf8')
  const built=await build({entryPoints:['/runner/runtime.mjs'],bundle:true,write:false,format:'iife',target:'es2022',minify:true,legalComments:'none',banner:{js:`/*! Leitor runtime Copyright (c) 2026 Emanoel IMS, MIT.\n${notices}\n*/`},plugins:[{name:'kit',setup(b){b.onResolve({filter:/^\/kit\//},args=>({path:`/runner/kit/${args.path.slice(5)}`}));b.onResolve({filter:/^\/leitor\//},args=>({path:`/runner/leitor/${args.path.slice(8)}`}))}}]})
  const bundle=built.outputFiles[0].text
  if(Buffer.byteLength(bundle)>1_000_000)throw Error('Bundle exceeds one megabyte')
  await writeFile(`${output}/bundle.js`,bundle)
  const kit=await readFile('/runner/kit/iso.css','utf8')
  const style=`${kit}\nhtml,body{margin:0;background:transparent;font-family:Arial,sans-serif}*{box-sizing:border-box}svg{max-width:100%;height:auto}button,input{font:inherit}#figure-root{width:100%;overflow:hidden}\n${request.css}`
  // Generated code never runs in Node. It is only parsed and bundled there.
  const html=`<!doctype html><html data-theme="light"><head><meta charset="utf-8"><meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; img-src data:; connect-src 'none'; frame-src 'none'; worker-src 'none'; form-action 'none'; base-uri 'none'"><style>${style.replace(/<\/style/gi,'')} html[data-theme=light] body{background:#faf9f6}html[data-theme=dark] body{background:#141310}</style></head><body><main id="figure-root"></main><script>${bundle.replace(/<\/script/gi,'<\\/script')}</script></body></html>`
  browser=await chromium.launch({executablePath:'/usr/bin/chromium',headless:true,args:['--no-sandbox','--disable-dev-shm-usage','--disable-background-networking','--js-flags=--max-old-space-size=128']})
  report.toolchain.chromium=browser.version()
  const context=await browser.newContext({viewport:{width:900,height:800},reducedMotion:'reduce'})
  await context.route('**/*',route=>{report.network.push(route.request().url().slice(0,200));return route.abort()})
  page=await context.newPage()
  page.on('pageerror',error=>report.errors.push(error.message.slice(0,400)))
  page.setDefaultTimeout(5000)
  await page.setContent(html,{waitUntil:'load',timeout:15000})
  await ready(page)
  report.model_checks=await page.evaluate(()=>JSON.parse(document.documentElement.dataset.modelChecks||'[]'))
  if(request.model_checks_required&&(report.model_checks.length<3||report.model_checks.length>24))throw Error('Provide 3–24 named mechanical checks')
  if(request.model_only){report.model_only=true}
  else {
    if(!await page.locator('svg,canvas').count())throw Error('The figure must contain a drawing')
    const drawing=()=>page.locator('#figure-root svg').evaluateAll(nodes=>nodes.map(node=>node.outerHTML).join(''))
    const initialDrawing=await drawing()
    if(await page.locator('#figure-root').evaluate(node=>node.getBoundingClientRect().height)>1400)throw Error('The figure exceeds the reader frame height')
    const initial=await page.screenshot({type:'png',fullPage:true})
    await writeFile(`${output}/light.png`,initial);report.images.push('light.png')
    for(const [index,experiment] of request.experiments.entries()) {
      for(const [stepIndex,step] of experiment.steps.entries()) {
        await perform(page,step)
        if(!request.capture_steps?.length&&index===request.experiments.length-1&&stepIndex===experiment.steps.length-2) {
          await page.screenshot({path:`${output}/detail.png`,type:'png',fullPage:true});report.images.push('detail.png')
        }
      }
      const actual=await page.locator(experiment.selector).innerText()
      if(!actual.includes(experiment.contains))throw Error(`Experiment ${index+1}: expected ${JSON.stringify(experiment.contains)}, received ${JSON.stringify(actual).slice(0,300)}`)
      report.checks.push({name:experiment.name,passed:true})
      if(initialDrawing&&await drawing()!==initialDrawing)report.drawing_changes++
    }
    if(initialDrawing&&!report.drawing_changes)throw Error('Controls changed text but never changed the drawing')
    const capture=request.capture_steps||[]
    if(capture.length) {
      report.tested_state=await captureState(page)
      await page.screenshot({path:`${output}/tested.png`,type:'png',fullPage:true});report.images.push('tested.png')
    }
    for(const [index,step] of capture.entries()) {
      await perform(page,step)
      if(index===capture.length-2) {
        await page.screenshot({path:`${output}/detail.png`,type:'png',fullPage:true});report.images.push('detail.png')
      }
    }
    report.capture_steps=capture.length
    report.capture_state=await captureState(page)
    const settled=await drawing()
    await page.waitForTimeout(200)
    if(settled!==await drawing())throw Error('The drawing is still animating with reduced motion enabled')
    report.reduced_motion_stable=true
    await page.screenshot({path:`${output}/interaction.png`,type:'png',fullPage:true});report.images.push('interaction.png')
    await page.evaluate(()=>{document.documentElement.dataset.theme='dark';document.getElementById('figure-root').dataset.theme='dark';document.getElementById('figure-root').dispatchEvent(new CustomEvent('figure:environment',{detail:{theme:'dark',visible:true,reducedMotion:true}}))})
    await page.screenshot({path:`${output}/dark.png`,type:'png',fullPage:true});report.images.push('dark.png')
    const mobile=await context.newPage();mobile.setDefaultTimeout(5000)
    mobile.on('pageerror',error=>report.errors.push(error.message.slice(0,400)))
    await mobile.setViewportSize({width:390,height:844})
    await mobile.setContent(html,{waitUntil:'load',timeout:15000})
    await ready(mobile)
    const overflow=await mobile.evaluate(()=>document.documentElement.scrollWidth>innerWidth)
    if(overflow)throw Error('The figure overflows a 390px viewport')
    if(await mobile.locator('#figure-root').evaluate(node=>node.getBoundingClientRect().height)>1400)throw Error('Mobile controls exceed the reader frame height')
    await mobile.screenshot({path:`${output}/mobile.png`,type:'png',fullPage:true});report.images.push('mobile.png')
    if(await mobile.locator('#figure-root svg').count()) {
      report.mobile_framing=await mobileFraming(mobile)
      if(report.mobile_framing.clipped)throw Error('The mobile drawing is clipped by its SVG viewBox. Fit the whole assembly and its travel into the default 390px view; a hidden overflow or automatic detail crop does not fix framing. Keep inspection detail in a separately labeled optional view.')
    }
    await mobile.close()
    await context.close()
    const motionContext=await browser.newContext({viewport:{width:900,height:800},reducedMotion:'no-preference'})
    await motionContext.route('**/*',route=>{report.network.push(route.request().url().slice(0,200));return route.abort()})
    const motion=await motionContext.newPage();motion.setDefaultTimeout(5000)
    motion.on('pageerror',error=>report.errors.push(error.message.slice(0,400)))
    await motion.setContent(html,{waitUntil:'load',timeout:15000})
    await ready(motion)
    report.animation_observed=false
    // All control assertions already ran above. This separate pass only needs
    // one observed time-dependent drawing change; stop before replaying costly
    // mechanical experiments unnecessarily under continuous animation.
    motionProbe: for(const experiment of request.experiments) {
      for(const step of experiment.steps) {
        await perform(motion,step)
        const at=await motion.locator('#figure-root svg').evaluateAll(nodes=>nodes.map(node=>node.outerHTML).join(''))
        await motion.waitForTimeout(140)
        const later=await motion.locator('#figure-root svg').evaluateAll(nodes=>nodes.map(node=>node.outerHTML).join(''))
        if(at&&at!==later){report.animation_observed=true;break motionProbe}
      }
    }
    if(request.motion_required&&!report.animation_observed) {
      const play=motion.getByRole('button',{name:/reproduzir|play|iniciar animação|start animation/i})
      if(await play.count()===1) {
        await play.click()
        const at=await motion.locator('#figure-root svg').evaluateAll(nodes=>nodes.map(node=>node.outerHTML).join(''))
        await motion.waitForTimeout(200)
        const later=await motion.locator('#figure-root svg').evaluateAll(nodes=>nodes.map(node=>node.outerHTML).join(''))
        report.animation_observed=Boolean(at&&at!==later)
      }
    }
    await motionContext.close()
    if(request.motion_required&&!report.animation_observed)throw Error('Playback did not produce time-dependent drawing motion. Provide a working play/pause control and verify elapsed frame time advances the actual mechanism; changing button text alone is insufficient.')
    await writeFile(`${output}/style.css`,style)
  }
  if(report.errors.length||report.network.length)throw Error('Runtime errors or network attempts detected')
  report.ok=true
} catch(error) {
  report.errors.push(String(error.message).slice(0,1500))
  if(page)try{report.model_checks=await page.evaluate(()=>JSON.parse(document.documentElement.dataset.modelChecks||'[]'))}catch{}
} finally {
  await browser?.close()
  await writeFile(`${output}/report.json`,JSON.stringify(report))
}
