import {expect} from "@playwright/test"

export async function signIn(page) {
  const email = `pages-${Date.now()}-${Math.random().toString(36).slice(2)}@example.test`
  await page.goto("/users/register")
  await page.locator("[data-phx-main].phx-connected").waitFor()
  await page.locator("#registration_form").getByLabel("Email", {exact: true}).fill(email)
  await page.locator("#register-submit").click()
  await page.waitForURL("**/users/log-in")
  await page.locator("[data-phx-main].phx-connected").waitFor()
  await page.locator("#login_form_magic").getByLabel("Email", {exact: true}).fill(email)
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
  await page.goto("/pages")
  await page.locator("#library-texts").waitFor()
}
