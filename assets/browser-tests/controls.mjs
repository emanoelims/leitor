import {expect} from '@playwright/test'

export async function chooseOption(page, control, value) {
  const id=await control.evaluate(el=>el.tagName==='SELECT' ? el.id : el.id.replace(/-trigger$/,''))
  const native=page.locator(`[id="${id}"]`)
  const index=await native.evaluate((el,value)=>Array.from(el.options).findIndex(option=>option.value===value),value)
  expect(index).toBeGreaterThanOrEqual(0)
  await page.locator(`[id="${id}-trigger"]`).click()
  await page.locator(`[id="${id}-options"] [data-option-index="${index}"]`).click()
  await expect(native).toHaveValue(value)
}

export async function openImport(page) {
  await page.locator('#page-create-trigger').click()
  await page.locator('#open-page-import').click()
  await expect(page.locator('#page-import-dialog')).toBeVisible()
}
