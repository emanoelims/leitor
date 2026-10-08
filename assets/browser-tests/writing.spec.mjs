import {test, expect} from "@playwright/test"

import {signIn, paste} from "./writing_helpers.mjs"

test.beforeEach(async ({page}) => { await signIn(page) })

test("slash menu uses the keyboard, escapes, filters, and keeps focus", async ({page}) => {
  const errors = []
  page.on("pageerror", error => errors.push(error.message))
  const editor = page.getByRole("textbox", {name: "Your English text", exact: true})
  await editor.pressSequentially("/heading")
  await expect(page.getByRole("listbox", {name: "Block types"})).toBeVisible()
  await editor.press("ArrowDown")
  await editor.press("Enter")
  await editor.pressSequentially("A quieter morning")
  await expect(editor.locator("h2")).toHaveText("A quieter morning")
  await editor.press("Enter")
  await editor.pressSequentially("/check")
  await editor.press("Enter")
  await editor.pressSequentially("Read one page")
  await expect(editor.getByRole("checkbox")).toBeVisible()
  await editor.getByRole("checkbox").check({timeout: 5000})
  await expect(page.locator("#writing_text")).toHaveValue(/\[x\] Read one page/)
  await editor.press("End")
  await editor.press("Enter")
  await editor.press("Enter")
  await editor.pressSequentially("/xyz")
  await expect(page.locator("#writing-block-empty")).toBeVisible()
  await editor.press("Escape")
  await expect(page.locator("#writing-block-menu")).toBeHidden()
  await expect(editor).toBeFocused()
  expect(errors).toEqual([])
})

test("Markdown survives preview, save, reload, history, Unicode, and mobile layout", async ({page}) => {
  const editor = page.getByRole("textbox", {name: "Your English text", exact: true})
  await paste(page, "# Café by the river\n\nA **small** moment with *friends*.\n\n- One memory\n- Another memory\n\n> Stay curious\n\n```elixir\nIO.puts(\"hello\")\n```")
  await expect(editor.locator("strong")).toHaveText("small")
  await expect(editor.locator("pre")).toContainText('IO.puts("hello")')
  await expect(page.locator("#writing-save-status")).toContainText("Unsaved changes")
  const source = await page.locator("#writing_text").inputValue()
  await page.locator("#writing-preview-toggle").click()
  await expect(page.locator("#writing-preview h1")).toHaveText("Café by the river")
  await expect(page.locator("#writing-preview strong")).toHaveText("small")
  await page.locator("#writing-preview-toggle").click()
  await page.locator("#save-draft").click()
  await expect(page.locator("#writing-save-status")).toContainText("Draft saved")
  await page.reload()
  await page.locator("[data-phx-main].phx-connected").waitFor()
  await page.locator("#writing-history-toggle").click()
  await page.locator(".writing-history-open").first().click()
  await expect(page.locator("#writing_text")).toHaveValue(source)
  await expect(editor.locator("strong")).toHaveText("small")
  await page.screenshot({path: "../tmp/writing-markdown-desktop.png"})
  await page.setViewportSize({width: 320, height: 740})
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true)
  await page.screenshot({path: "../tmp/writing-markdown-mobile.png"})
})

test("Markdown shortcuts, undo, and the document limit preserve existing text", async ({page}) => {
  const editor = page.getByRole("textbox", {name: "Your English text", exact: true})
  await editor.pressSequentially("## A heading")
  await expect(editor.locator("h2")).toHaveText("A heading")
  await editor.press("Enter")
  await editor.pressSequentially("**Bold** ")
  await expect(editor.locator("strong")).toHaveText("Bold")
  await editor.press("Enter")
  await paste(page, "Undo this sentence.")
  await expect(editor).toContainText("Undo this sentence.")
  await editor.press("ControlOrMeta+z")
  await expect(editor).not.toContainText("Undo this sentence.")
  const source = await page.locator("#writing_text").inputValue()
  await paste(page, "x".repeat(10001))
  await expect(page.locator("#writing_text")).toHaveValue(source)
  await expect(page.locator("#writing-editor-status")).toContainText("10,000")
})

test("legacy drafts keep literal Markdown, including long escaped content", async ({page}) => {
  const legacy = "*".repeat(9000)
  // Reproduce the plain-text payload saved by the previous editor.
  await page.locator("#writing_text").evaluate((input, text) => {
    input.value = text
    input.dispatchEvent(new Event("input", {bubbles: true}))
  }, legacy)
  await page.locator("#save-draft").click()
  await expect(page.locator("#writing-save-status")).toContainText("Draft saved")
  await page.reload()
  await page.locator("[data-phx-main].phx-connected").waitFor()
  await page.locator("#writing-history-toggle").click()
  await page.locator(".writing-history-open").first().click()
  const editor = page.getByRole("textbox", {name: "Your English text", exact: true})
  await expect(editor.locator("p").first()).toHaveText(legacy)
  await expect(editor.locator("strong, em, hr")).toHaveCount(0)
  await expect(page.locator("#writing_text")).toHaveValue(legacy)
})


test("slash menu aligns its columns and stays anchored without scrolling the page", async ({page}) => {
  const editor = page.getByRole("textbox", {name: "Your English text", exact: true})
  await editor.pressSequentially("/")
  const menu = page.locator("#writing-block-menu")
  await expect(menu).toBeVisible()
  const rows = await menu.locator("[data-command]").evaluateAll(items => items.map(item => {
    const [icon, label, shortcut] = item.children
    return {icon: icon.getBoundingClientRect().toJSON(), label: label.getBoundingClientRect().toJSON(), shortcut: shortcut.getBoundingClientRect().toJSON()}
  }))
  for (const row of rows) {
    expect(row.icon.width).toBe(16)
    expect(row.label.x - row.icon.right).toBe(10)
    expect(Math.abs(row.label.x - rows[0].label.x)).toBeLessThan(1)
  }
  const caret = await editor.evaluate(() => window.getSelection().getRangeAt(0).getBoundingClientRect().toJSON())
  await expect.poll(async () => Math.abs((await menu.boundingBox()).x - caret.x)).toBeLessThan(2)
  await expect.poll(async () => Math.abs((await menu.boundingBox()).y - caret.bottom - 8)).toBeLessThan(2)
  const scroll = await page.evaluate(() => window.scrollY)
  for (let i = 0; i < 9; i++) await editor.press("ArrowDown")
  expect(await page.evaluate(() => window.scrollY)).toBe(scroll)
  await page.screenshot({path: "../tmp/writing-slash-desktop.png"})
  await page.setViewportSize({width: 320, height: 740})
  await expect.poll(async () => {
    const box = await menu.boundingBox()
    return box.x >= 11 && box.x + box.width <= 309 && box.y >= 0 && box.y + box.height <= 740
  }).toBe(true)
  await page.screenshot({path: "../tmp/writing-slash-mobile.png"})
})
