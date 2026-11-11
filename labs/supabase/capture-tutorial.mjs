import { chromium } from 'playwright'
import { readFile, writeFile, mkdir } from 'node:fs/promises'
import { fileURLToPath } from 'node:url'
import path from 'node:path'
import { createHash } from 'node:crypto'
import { execFileSync } from 'node:child_process'

const lab = path.dirname(fileURLToPath(import.meta.url))
const repo = path.resolve(lab, '../..')
const output = path.join(repo, 'docs/tutorials/supabase-self-hosted')
const env = Object.fromEntries((await readFile(path.join(lab, '.env'), 'utf8'))
  .split(/\r?\n/).filter(line => line.trim() && !line.trim().startsWith('#'))
  .map(line => {
    const at = line.indexOf('=')
    return [line.slice(0, at).trim(), line.slice(at + 1).trim().replace(/^['"]|['"]$/g, '')]
  }))
const base = env.SUPABASE_PUBLIC_URL.replace(/\/$/, '')
const upstream = JSON.parse(await readFile(path.join(lab, 'upstream.json'), 'utf8'))

// Verify the actual Auth/Data API/RLS behavior before taking tutorial images.
execFileSync('python3', [path.join(lab, 'lab.py'), 'verify'], { stdio: 'inherit', cwd: repo })
await mkdir(path.join(output, 'images'), { recursive: true })
const options = { headless: true }
if (process.env.PLAYWRIGHT_EXECUTABLE_PATH) options.executablePath = process.env.PLAYWRIGHT_EXECUTABLE_PATH
else if (process.env.PLAYWRIGHT_CHANNEL) options.channel = process.env.PLAYWRIGHT_CHANNEL
const browser = await chromium.launch(options)
const context = await browser.newContext({
  viewport: { width: 1600, height: 1000 }, deviceScaleFactor: 1, colorScheme: 'light',
  httpCredentials: { username: env.DASHBOARD_USERNAME, password: env.DASHBOARD_PASSWORD, origin: base },
})
const page = await context.newPage()
page.setDefaultTimeout(30000)
const captures = []
const sql = `SELECT claim_no, branch, amount, status
FROM public.claimsure_claims
ORDER BY claim_no;`

async function open(route) {
  const response = await page.goto(base + route, { waitUntil: 'domcontentloaded', timeout: 60000 })
  if (!response || response.status() >= 400) throw new Error(`Studio navigation failed: ${route}`)
}

async function visibleText(text) {
  await page.getByText(text, { exact: true }).first().waitFor({ state: 'visible' })
}

async function capture(file, title, assertions) {
  for (const text of assertions) await visibleText(text)
  await page.evaluate(() => Promise.race([document.fonts.ready, new Promise(r => setTimeout(r, 4000))]))
  await page.waitForTimeout(700)
  const filename = path.join(output, 'images', file)
  // No API-key/settings screen, HAR or authenticated browser state is saved.
  await page.screenshot({ path: filename, fullPage: true, animations: 'disabled', timeout: 20000 })
  captures.push({ step: captures.length + 1, title, url: page.url(), image: 'images/' + file,
    assertions, captured_at: new Date().toISOString(),
    sha256: createHash('sha256').update(await readFile(filename)).digest('hex') })
  console.log(`Captured ${file}`)
}

try {
  await open('/project/default')
  await capture('01-studio-overview.png', 'ClaimSure self-hosted Studio', ['ClaimSure Self-hosted Lab'])

  await open('/project/default/sql/new')
  const editor = page.locator('.monaco-editor textarea').first()
  await editor.waitFor({ state: 'attached' })
  await editor.focus()
  await page.keyboard.press('ControlOrMeta+A')
  await page.keyboard.insertText(sql)
  await page.getByRole('button', { name: /^Run\b/ }).first().click()
  await visibleText('CLM-BKK-001')
  const claimColumn = page.getByRole('columnheader', { name: 'claim_no', exact: true })
  const columnBox = await claimColumn.boundingBox()
  if (!columnBox) throw new Error('SQL result column did not render')
  // Resize the actual result grid through its UI so reference numbers fit.
  await page.mouse.move(columnBox.x + columnBox.width - 2, columnBox.y + columnBox.height / 2)
  await page.mouse.down()
  await page.mouse.move(columnBox.x + columnBox.width + 110, columnBox.y + columnBox.height / 2, { steps: 12 })
  await page.mouse.up()
  if ((await claimColumn.boundingBox()).width < 180) throw new Error('SQL claim_no column is too narrow')
  await capture('02-sql-editor.png', 'SQL Editor: four synthetic claims', ['CLM-BKK-001', 'CLM-CM-002'])

  await open('/project/default/auth/users')
  await capture('03-auth-users.png', 'Authentication: confirmed demo users', [env.DEMO_BKK_EMAIL, env.DEMO_CM_EMAIL])

  await open('/project/default/editor')
  await page.getByText('claimsure_claims', { exact: true }).first().click()
  await capture('04-table-editor.png', 'Table Editor: claimsure_claims', ['CLM-BKK-001', 'CLM-CM-002'])

  await open('/project/default/database/policies')
  await capture('05-rls-policies.png', 'RLS: SELECT, INSERT and UPDATE policies',
    ['claims_read_own', 'claims_insert_own', 'claims_update_own'])

  await open('/project/default/storage/files/buckets/claim-documents')
  await capture('06-private-storage.png', 'Storage: private claim documents', ['example-claim.txt'])
  await page.getByRole('button', { name: 'Edit bucket', exact: true }).click()
  await page.getByRole('menuitem', { name: 'Bucket settings', exact: true }).click()
  const publicBucket = page.getByRole('switch', { name: 'Public bucket', exact: true })
  if (await publicBucket.getAttribute('aria-checked') !== 'false') throw new Error('Storage bucket is public')
  await capture('07-storage-settings.png', 'Storage: Public bucket switched off', ['Public bucket'])
  captures[captures.length - 1].public_bucket = false
  await page.getByRole('button', { name: 'Cancel', exact: true }).click()

  await writeFile(path.join(output, 'capture-manifest.json'), JSON.stringify({
    base_url: base, upstream_revision: upstream.revision,
    playwright_version: JSON.parse(await readFile(path.join(lab, 'node_modules/playwright/package.json'), 'utf8')).version,
    browser_version: browser.version(), viewport: { width: 1600, height: 1000 },
    data: 'Synthetic ClaimSure demo only',
    capture_method: 'Playwright screenshots of the running self-hosted Studio; no mocked responses',
    verification: 'verification.json', captures,
  }, null, 2) + '\n')
  console.log(`PASS: ${captures.length} real Studio screenshots and capture-manifest.json`)
  await import('./render-tutorial.mjs')
} finally {
  await context.close()
  await browser.close()
}
