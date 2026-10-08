import {test, expect} from "@playwright/test"

async function signIn(page) {
  const email = `markdown-${Date.now()}-${Math.random().toString(36).slice(2)}@example.test`
  await page.goto("/users/log-in")
  await page.locator("[data-phx-main].phx-connected").waitFor()
  await page.getByLabel("Email", {exact: true}).fill(email)
  await page.locator("#magic-link-submit").click()
  let link
  await expect.poll(async () => {
    const response = await page.request.get("/dev/mailbox/json")
    const message = (await response.json()).data.find(item => item.to.some(recipient => recipient.includes(email)))
    link = message?.text_body.match(/http[^\s]+\/users\/log-in\/[^\s]+/)?.[0]
    return Boolean(link)
  }).toBe(true)
  await page.goto(link)
  await page.locator("[data-phx-main].phx-connected").waitFor()
  await page.locator("#confirm-submit").click()
  await page.waitForURL(url => !url.pathname.startsWith("/users/log-in"))
  await page.goto("/write")
  await page.getByRole("textbox", {name: "Your English text", exact: true}).waitFor()
}

async function paste(page, text) {
  await page.getByRole("textbox", {name: "Your English text", exact: true}).evaluate((el, content) => {
    el.focus()
    const clipboardData = new DataTransfer()
    clipboardData.setData("text/plain", content)
    el.dispatchEvent(new ClipboardEvent("paste", {bubbles: true, cancelable: true, clipboardData}))
  }, text)
}

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
