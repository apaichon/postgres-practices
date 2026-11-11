import { chromium } from 'playwright'
import { readFile, writeFile } from 'node:fs/promises'
import { fileURLToPath } from 'node:url'
import path from 'node:path'
import { createHash } from 'node:crypto'

const lab = path.dirname(fileURLToPath(import.meta.url))
const output = path.resolve(lab, '../../docs/tutorials/supabase-self-hosted')
const env = Object.fromEntries((await readFile(path.join(lab, '.env'), 'utf8'))
  .split(/\r?\n/).filter(line => line.trim() && !line.trim().startsWith('#'))
  .map(line => {
    const index = line.indexOf('=')
    return [line.slice(0, index).trim(), line.slice(index + 1).trim().replace(/^['"]|['"]$/g, '')]
  }))
const options = { headless: true }
if (process.env.PLAYWRIGHT_EXECUTABLE_PATH) options.executablePath = process.env.PLAYWRIGHT_EXECUTABLE_PATH
else if (process.env.PLAYWRIGHT_CHANNEL) options.channel = process.env.PLAYWRIGHT_CHANNEL
const browser = await chromium.launch(options)
const context = await browser.newContext({
  viewport: { width: 1600, height: 1000 }, colorScheme: 'light',
  httpCredentials: { username: env.DASHBOARD_USERNAME, password: env.DASHBOARD_PASSWORD,
    origin: env.SUPABASE_PUBLIC_URL },
})
try {
  const page = await context.newPage()
  await page.goto(env.SUPABASE_PUBLIC_URL + '/project/default/auth/users', { waitUntil: 'domcontentloaded' })
  await page.getByText(env.DEMO_BKK_EMAIL, { exact: true }).waitFor()
  await page.getByRole('button', { name: 'Add user', exact: true }).click()
  await page.getByRole('menuitem', { name: /Create new user/ }).click()
  const dialog = page.getByRole('dialog')
  await dialog.waitFor()
  const password = dialog.locator('input[type="password"]')
  if (await password.inputValue() !== '') throw new Error('Only a blank form may be captured')
  await page.evaluate(() => document.fonts.ready)
  await page.waitForTimeout(500)
  const file = 'images/08-user-guide-create-user.png'
  await dialog.screenshot({ path: path.join(output, file), animations: 'disabled' })
  await writeFile(path.join(output, 'user-guide-capture.json'), JSON.stringify({
    captured_at: new Date().toISOString(), url: page.url(), image: file,
    sha256: createHash('sha256').update(await readFile(path.join(output, file))).digest('hex'),
    method: 'Playwright element screenshot, real Studio, blank Create new user form; no user submitted',
    dialog_labels: await dialog.locator('label').allTextContents(),
  }, null, 2) + '\n')
  console.log('Captured blank Create new user form. No user was created.')
} finally {
  await context.close()
  await browser.close()
}
