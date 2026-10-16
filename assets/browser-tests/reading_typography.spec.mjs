import {test, expect} from '@playwright/test'
import {signIn} from './authentication.mjs'
import {openImport} from './controls.mjs'

test('reading typography matches Gloss across faces, sizes, leading and the mobile breakpoint',async({page},testInfo)=>{
  await signIn(page)
  await openImport(page)
  await page.getByLabel('Text to import',{exact:true}).fill('# Typography reference\n\n## A thoughtful section\n\nA quiet paragraph gives each line enough room to breathe. The words should feel evenly spaced and comfortable to follow.\n\nAnother paragraph continues the thought with a familiar rhythm.\n\n### A smaller section\n\nThe final paragraph closes this reading sample.')
  await page.locator('#save-material').click()
  await page.locator('#library-texts article h2').click()
  await expect(page.locator('#page-reading')).toBeVisible()
  await expect(page.locator('.free-page')).toHaveClass(/page-size-20/)
  for(const width of [1440,641,640,390]){
    await page.setViewportSize({width,height:960})
    const rows=await page.locator('#page-reading').evaluate(el=>{
      const root=el.closest('.free-page'),classes=root.className,style=root.getAttribute('style'),rows=[]
      const read=node=>{const s=getComputedStyle(node);return {size:parseFloat(s.fontSize),leading:parseFloat(s.lineHeight),gap:parseFloat(s.marginBottom)}}
      for(const face of ['serif','sans','book','legible'])for(const leading of ['tight','normal','loose'])for(const size of [15,20,28]){
        root.classList.remove('page-face-serif','page-face-sans','page-face-book','page-face-legible','page-leading-tight','page-leading-normal','page-leading-loose')
        root.classList.add(`page-face-${face}`,`page-leading-${leading}`)
        root.style.setProperty('--page-text-size',`${size}px`)
        rows.push({face,leading,size,paragraph:read(el.querySelector('p')),h2:read(el.querySelector('h2')),h3:read(el.querySelector('h3'))})
      }
      root.className=classes
      root.setAttribute('style',style)
      return rows
    })
    for(const row of rows){
      const factor={serif:width<=640?.9:1,sans:width<=640?.84:.9,book:.94,legible:.88}[row.face]
      const size=row.size*factor,leading={tight:1.5,normal:1.64,loose:1.82}[row.leading]-(width<=640?.05:0)
      expect(row.paragraph.size).toBeCloseTo(size,2)
      expect(row.paragraph.leading).toBeCloseTo(size*leading,2)
      expect(row.paragraph.gap).toBeCloseTo(size*.95,2)
      expect(row.h2.size).toBeCloseTo(size*1.32,2)
      expect(row.h2.leading).toBeCloseTo(size*1.32*1.25,2)
      expect(row.h3.size).toBeCloseTo(size*1.08,2)
      expect(row.h3.leading).toBeCloseTo(size*1.08*1.3,2)
    }
    if(width===1440||width===390)await page.screenshot({path:testInfo.outputPath(`reading-rhythm-${width}.png`),fullPage:true})
  }
})
