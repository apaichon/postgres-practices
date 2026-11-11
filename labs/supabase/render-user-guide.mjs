import MarkdownIt from 'markdown-it'
import { readFile, writeFile, mkdir } from 'node:fs/promises'
import { fileURLToPath, pathToFileURL } from 'node:url'
import path from 'node:path'
import { execFileSync } from 'node:child_process'

const lab = path.dirname(fileURLToPath(import.meta.url))
const repo = path.resolve(lab, '../..')
const dir = path.join(repo, 'docs/tutorials/supabase-self-hosted')
const md = new MarkdownIt({ html: false, linkify: true })
const tokens = md.parse(await readFile(path.join(dir, 'USER-GUIDE.md'), 'utf8'), {})
const chapters = []
let firstChapter = -1
for (let index = 0; index < tokens.length; index++) {
  if (tokens[index].type === 'heading_open' && tokens[index].tag === 'h2') {
    if (firstChapter < 0) firstChapter = index
    const id = `chapter-${chapters.length + 1}`
    tokens[index].attrSet('id', id)
    chapters.push({ id, index, title: tokens[index + 1].content })
  }
}
const esc = md.utils.escapeHtml
const links = chapters.map(row => `<a href="#${row.id}">${esc(row.title)}</a>`).join('\n')
const render = rows => md.renderer.render(rows, md.options, {})
const body = chapters.map((row, index) => `<section class="chapter">${render(tokens.slice(row.index, chapters[index + 1]?.index))}</section>`).join('\n')
const html = `<!doctype html><html lang="th"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>คู่มือใช้งาน Supabase Self-hosted - ClaimSure</title>
<style>
:root{color-scheme:light;--ink:#173952;--navy:#12365d;--blue:#147cb4;--line:#cfdfec;--muted:#50697d}
*{box-sizing:border-box}html{scroll-behavior:smooth}body{margin:0;background:#f4f8fc;color:var(--ink);font:17px/1.8 'Thonburi','Noto Sans Thai','Leelawadee UI',system-ui,sans-serif}
.top{background:var(--navy);color:white;padding:24px max(24px,calc((100vw - 1320px)/2));border-bottom:5px solid #3bb4ee}.top strong{display:block;font-size:23px}.top small{color:#b9e3fa;font-size:13px;letter-spacing:.06em}
.layout{display:grid;grid-template-columns:235px minmax(0,1fr);gap:36px;max-width:1360px;padding:36px 24px 80px;margin:auto}aside{position:sticky;top:18px;align-self:start;max-height:94vh;overflow:auto;font-size:13px;padding-right:12px}aside a{display:block;padding:7px 0;border-bottom:1px solid var(--line);line-height:1.8}aside strong{display:block;margin-bottom:10px}
main{min-width:0;background:white;border:1px solid var(--line);padding:38px 42px}h1,h2,h3{color:var(--navy);line-height:1.5}h1{font-size:34px;margin:0 0 22px}h2{font-size:27px;margin:0 0 22px;scroll-margin-top:24px}h3{font-size:20px;margin:28px 0 10px}p,ul,ol{margin:15px 0}li{margin:7px 0}a{color:var(--blue);text-decoration:none;overflow-wrap:anywhere}a:hover{text-decoration:underline}
.brand{font:700 13px/1.5 system-ui,sans-serif;letter-spacing:.12em;color:#147cb4;margin-bottom:34px}.cover{padding:8px 0 24px}.cover h1{max-width:700px}.cover p:first-of-type{font-size:22px;color:var(--blue)}.download{padding:18px 0;border-top:1px solid var(--line);font-size:14px}.download a{margin-right:18px}.contents{margin:20px 0 46px;padding:25px 0;border-top:2px solid var(--line)}.contents h2{font-size:24px}.contents a{display:block;font-size:15px;padding:6px 0}.chapter{padding:38px 0 10px;border-top:2px solid var(--line);margin-top:30px}
.table-scroll{overflow:auto;margin:24px 0}table{width:100%;border-collapse:collapse;font-size:14px}th{background:#edf6fc;color:var(--navy);text-align:left}th,td{border:1px solid var(--line);padding:9px 11px;vertical-align:top}
code{font:13px/1.65 ui-monospace,SFMono-Regular,Consolas,monospace;background:#edf3f8;border-radius:3px;padding:2px 4px;overflow-wrap:anywhere}pre{background:#102b44;color:#ecf6ff;padding:23px 18px 18px;border-left:4px solid #39b6ed;border-radius:4px;overflow:auto;font-size:13px}pre code{background:none;color:inherit;padding:0;white-space:pre;overflow-wrap:normal}
.code-wrap{position:relative}.copy{position:absolute;right:8px;top:7px;padding:2px 8px;background:#eff8ff;border:1px solid #9fbad0;border-radius:3px;font:12px system-ui,sans-serif;color:#12365d;cursor:pointer}
main img{width:100%;height:auto;display:block;border:1px solid #bccedd;border-radius:4px;margin:24px 0;cursor:zoom-in}dialog{max-width:96vw;max-height:96vh;padding:8px;border:0;border-radius:5px}dialog::backdrop{background:#03182fe6}dialog img{max-width:92vw;max-height:88vh;width:auto;display:block;cursor:zoom-out}
@media(max-width:1050px){.layout{grid-template-columns:1fr;gap:20px}aside{position:static;max-height:230px}main{padding:25px}h1{font-size:28px}h2{font-size:24px}.top strong{font-size:21px}}
@page{size:A4;margin:20mm 17mm}
@media print{html{scroll-behavior:auto}body{background:white;color:#172d40;font-size:10.3pt;line-height:1.65}.top,aside,.download,dialog,.copy{display:none!important}.layout{display:block;max-width:none;margin:0;padding:0}main{border:0;padding:0}.brand{font-size:10pt;margin:0 0 25mm}.cover{min-height:250mm;break-after:page;padding:12mm 0 0}.cover h1{font-size:30pt;line-height:1.5;margin:0 0 10mm}.cover p:first-of-type{font-size:16pt;margin:0 0 12mm}.cover p{margin:6mm 0;max-width:170mm}.contents{margin:0;padding:0;border:0;break-after:page}.contents h2{font-size:22pt;margin-bottom:10mm}.contents a{font-size:12pt;padding:3mm 0;border-bottom:1px solid #dbe6ee}.chapter{margin:0;padding:0;border:0;break-before:page}h2{font-size:20pt;margin:0 0 6mm;break-after:avoid}h3{font-size:12pt;margin:6mm 0 2mm;break-after:avoid}p,ul,ol{margin:3mm 0}p,li{orphans:3;widows:3}li{margin:1.5mm 0}a{color:#145e8b}table{font-size:9pt;line-height:1.55;break-inside:auto}th,td{padding:2.2mm 2.5mm;overflow-wrap:anywhere}thead{display:table-header-group}tr{break-inside:avoid}.table-scroll{overflow:visible;margin:4mm 0}code{font-size:8.5pt}pre{background:#eef4fa!important;color:#142c40!important;padding:4mm;border-left:2px solid #2b96ca;white-space:pre-wrap;overflow:visible;break-inside:avoid}pre code{white-space:pre-wrap;overflow-wrap:anywhere;color:#142c40!important}.code-wrap{break-inside:avoid}main img{max-height:110mm;object-fit:contain;border-radius:0;margin:4mm 0}p:has(img){break-inside:avoid;break-after:avoid}}
</style><style>
code{font-family:ui-monospace,SFMono-Regular,Consolas,'Thonburi',monospace}
main img[src*="08-user-guide"]{width:auto;max-width:100%;max-height:500px;margin-inline:auto}
@media print{ol{break-inside:avoid}.chapter:has(#chapter-7) h3:first-of-type{break-before:page}main img[src*="08-user-guide"]{max-height:90mm}}
</style></head><body>
<header class="top"><small>CLAIMSURE ACADEMY | USER GUIDE</small><strong>คู่มือใช้งาน Supabase Self-hosted</strong></header>
<div class="layout"><aside aria-label="สารบัญ"><strong>เลือกหัวข้อที่ต้องการ</strong>${links}<p><a href="../../../output/pdf/supabase-self-hosted-user-guide-th.pdf">ดาวน์โหลด PDF</a><a href="USER-GUIDE.md">Markdown Source</a><a href="index.html">Tutorial เดิม</a></p></aside><main>
<section class="cover"><div class="brand">CLAIMSURE ACADEMY<br>SUPABASE SELF-HOSTED | USER GUIDE</div>${render(tokens.slice(0, firstChapter))}<div class="download"><a href="../../../output/pdf/supabase-self-hosted-user-guide-th.pdf">ดาวน์โหลด PDF</a><a href="USER-GUIDE.md">Markdown</a></div></section>
<section class="contents"><h2>สารบัญ</h2>${links}</section>${body}
</main></div><dialog aria-label="ภาพหน้าจอขนาดเต็ม"><img alt=""></dialog>
<script>
for(const table of document.querySelectorAll('table')){const box=document.createElement('div');box.className='table-scroll';table.replaceWith(box);box.append(table)}
const dialog=document.querySelector('dialog');for(const image of document.querySelectorAll('main img')){image.tabIndex=0;const show=()=>{const big=dialog.querySelector('img');big.src=image.src;big.alt=image.alt;dialog.showModal()};image.addEventListener('click',show);image.addEventListener('keydown',event=>{if(event.key==='Enter')show()})}dialog.addEventListener('click',()=>dialog.close());
for(const pre of document.querySelectorAll('pre')){const box=document.createElement('div');box.className='code-wrap';pre.replaceWith(box);box.append(pre);const button=document.createElement('button');button.className='copy';button.textContent='คัดลอก';button.addEventListener('click',async()=>{try{await navigator.clipboard.writeText(pre.innerText);button.textContent='คัดลอกแล้ว'}catch{const range=document.createRange();range.selectNodeContents(pre);const selection=getSelection();selection.removeAllRanges();selection.addRange(range);button.textContent='เลือกข้อความแล้ว'}});box.append(button)}
</script></body></html>`
const target = path.join(dir, 'user-guide.html')
await writeFile(target, html)
console.log('Rendered ' + path.relative(repo, target))

if (process.argv.includes('--pdf')) {
  const { chromium } = await import('playwright')
  const options = { headless: true }
  if (process.env.PLAYWRIGHT_EXECUTABLE_PATH) options.executablePath = process.env.PLAYWRIGHT_EXECUTABLE_PATH
  else if (process.env.PLAYWRIGHT_CHANNEL) options.channel = process.env.PLAYWRIGHT_CHANNEL
  const browser = await chromium.launch(options)
  const temporary = path.join(repo, 'tmp/pdfs/supabase-user-guide')
  const pdf = path.join(repo, 'output/pdf/supabase-self-hosted-user-guide-th.pdf')
  await mkdir(temporary, { recursive: true })
  await mkdir(path.dirname(pdf), { recursive: true })
  try {
    const page = await browser.newPage()
    await page.goto(pathToFileURL(target).href)
    await page.waitForFunction(() => [...document.querySelectorAll('main img')].every(image => image.complete && image.naturalWidth > 0))
    await page.evaluate(() => document.fonts.ready)
    await page.pdf({ path: path.join(temporary, 'body.pdf'), preferCSSPageSize: true,
      printBackground: true, tagged: true, outline: true })
  } finally { await browser.close() }
  // Chromium shapes Thai text; ReportLab adds consistent running page furniture.
  execFileSync('python3', [path.join(lab, 'stamp-user-guide.py'), path.join(temporary, 'body.pdf'), pdf], { stdio: 'inherit' })
}
