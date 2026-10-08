import {expect} from "@playwright/test"

export async function signIn(page) {
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
  }, {timeout: 15000}).toBe(true)
  await page.goto(link)
  await page.locator("[data-phx-main].phx-connected").waitFor()
  await page.locator("#confirm-submit").click()
  await page.waitForURL(url => !url.pathname.startsWith("/users/log-in"))
  await page.goto("/write")
  await page.getByRole("textbox", {name: "Your English text", exact: true}).waitFor()
}

export async function paste(page, text) {
  await page.getByRole("textbox", {name: "Your English text", exact: true}).evaluate((el, content) => {
    el.focus()
    const clipboardData = new DataTransfer()
    clipboardData.setData("text/plain", content)
    el.dispatchEvent(new ClipboardEvent("paste", {bubbles: true, cancelable: true, clipboardData}))
  }, text)
}

