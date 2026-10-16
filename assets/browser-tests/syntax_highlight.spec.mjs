import {test, expect} from '@playwright/test'
import {signIn} from './authentication.mjs'
import {openImport} from './controls.mjs'

test('Lumis follows reading themes and preserves annotations after code on desktop and mobile', async ({page}, testInfo) => {
  const errors=[]
  page.on('pageerror', error=>errors.push(error.message))
  await page.emulateMedia({reducedMotion:'reduce',colorScheme:'light'})
  await signIn(page)
  await openImport(page)
  await page.getByLabel('Text to import',{exact:true}).fill(`# Code and quiet thoughts

A short example, safe to read.

\`\`\`elixir
def hello(name), do: "Olá, #{name}"
\`\`\`

After the code, keep this thought.

\`\`\`js
const message = "Hello";
console.log(message);
\`\`\`

\`\`\`unknown-language
<script>window.untrustedCodeRan = true</script>
\`\`\`
`)
  await page.locator('#save-material').click()
  await page.locator('#library-texts article h2').click()
  await expect(page.locator('#page-reading pre.lumis')).toHaveCount(3)
  const keyword=page.locator('#page-reading .l-keyword-function').first()
  await expect(keyword).toHaveText('def')
  const code=page.locator('#page-reading code.language-elixir')
  expect(await code.textContent()).toBe('def hello(name), do: "Olá, #{name}"\n')
  expect(await page.evaluate(()=>window.untrustedCodeRan)).toBeUndefined()
  await expect(page.locator('#page-reading script')).toHaveCount(0)

  const paragraph=page.locator('[data-page-block]').filter({hasText:'After the code, keep this thought.'})
  await paragraph.evaluate(el=>{
    const text=el.querySelector('p').firstChild, range=document.createRange()
    range.setStart(text,0);range.setEnd(text,14)
    const selection=window.getSelection();selection.removeAllRanges();selection.addRange(range)
    el.dispatchEvent(new MouseEvent('mouseup',{bubbles:true}))
  })
  await page.locator('#selection-note').click()
  await page.getByLabel('Your note on the selection').fill('Offsets stay correct after syntax highlighting.')
  await page.locator('#selection-note-form').getByRole('button',{name:'Keep note'}).click()
  await expect(paragraph.locator('mark')).toHaveText('After the code')
  await page.reload()
  await expect(paragraph.locator('mark')).toHaveText('After the code')

  await page.locator('#reading-font').click()
  const colors={}
  for(const theme of ['light','sepia','snow','dark','ink','auto']){
    await page.locator(`#reading-theme-${theme}`).click()
    colors[theme]=await keyword.evaluate(el=>getComputedStyle(el).color)
    expect(await code.textContent()).toBe('def hello(name), do: "Olá, #{name}"\n')
  }
  expect(colors.dark).not.toBe(colors.light)
  expect(colors.ink).toBe(colors.dark)
  expect(colors.sepia).toBe(colors.light)
  expect(colors.snow).toBe(colors.light)
  expect(colors.auto).toBe(colors.light)
  await page.keyboard.press('Escape')
  await page.emulateMedia({colorScheme:'dark'})
  await expect.poll(()=>keyword.evaluate(el=>getComputedStyle(el).color)).toBe(colors.dark)
  await page.screenshot({path:testInfo.outputPath('lumis-dark-desktop.png'),fullPage:true})
  await page.setViewportSize({width:390,height:844})
  expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true)
  await expect(code).toBeVisible()
  await page.screenshot({path:testInfo.outputPath('lumis-dark-mobile.png'),fullPage:true})
  expect(errors).toEqual([])
})
