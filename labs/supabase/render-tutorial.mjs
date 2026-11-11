import MarkdownIt from 'markdown-it'
import { readFile, writeFile } from 'node:fs/promises'
import { fileURLToPath } from 'node:url'
import path from 'node:path'

const lab = path.dirname(fileURLToPath(import.meta.url))
const dir = path.resolve(lab, '../../docs/tutorials/supabase-self-hosted')
const source = await readFile(path.join(dir, 'API-LAB.md'), 'utf8')
const md = new MarkdownIt({ html: false, linkify: true })
const tokens = md.parse(source, {})
const navigation = []
let section = 0
for (let i = 0; i < tokens.length; i++) {
  if (tokens[i].type === 'heading_open' && tokens[i].tag === 'h2') {
    const id = `step-${++section}`
    tokens[i].attrSet('id', id)
    navigation.push({ id, text: tokens[i + 1].content })
  }
}
const esc = md.utils.escapeHtml
const content = md.renderer.render(tokens, md.options, {})
const nav = navigation.map(row => `<a href="#${row.id}">${esc(row.text)}</a>`).join('\n')
await writeFile(path.join(dir, 'index.html'), `<!doctype html>
<html lang="th"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Lab 10 · Supabase Data API และ Authentication</title>
<style>
:root{color-scheme:light;--navy:#10355d;--blue:#157bb7;--line:#d6e5f0;--muted:#4b647b}
*{box-sizing:border-box}html{scroll-behavior:smooth}body{margin:0;background:#f6f9fc;color:#183650;font:17px/1.8 'Noto Sans Thai','Thonburi',system-ui,sans-serif}
header{padding:36px max(24px,calc((100vw - 1320px)/2));background:#10355d;color:white;border-bottom:5px solid #35b5ee}
header small{letter-spacing:.1em;color:#a5dfff}header div{font-size:27px;font-weight:700;margin-top:6px}
.layout{display:grid;grid-template-columns:240px minmax(0,1fr);gap:40px;max-width:1360px;padding:38px 24px 90px;margin:auto}
nav{align-self:start;position:sticky;top:20px;max-height:90vh;overflow:auto;font-size:13px;padding-right:15px}
nav strong{display:block;color:var(--navy);margin-bottom:12px}nav a{display:block;line-height:1.7;padding:7px 0;border-bottom:1px solid var(--line);color:var(--muted)}
main{background:white;border:1px solid var(--line);padding:30px 40px;min-width:0}h1,h2,h3{color:var(--navy);line-height:1.45}h1{font-size:32px;margin:0 0 22px}h2{font-size:25px;margin:50px 0 18px;padding-top:14px;border-top:2px solid var(--line);scroll-margin-top:20px}h3{font-size:21px}
a{color:var(--blue);text-decoration:none}a:hover{text-decoration:underline}p,ul{margin:16px 0}li{margin:6px 0}strong{font-weight:700}
img{display:block;width:100%;height:auto;margin:26px 0;border:1px solid #bdcddd;border-radius:6px;box-shadow:0 8px 22px #173b5910;cursor:zoom-in}
.table-scroll{overflow:auto;margin:24px 0}table{border-collapse:collapse;width:100%;font-size:15px}th{background:#eaf5fc;color:var(--navy);text-align:left}th,td{border:1px solid var(--line);padding:10px 13px;vertical-align:top}
code{font:14px/1.7 ui-monospace,SFMono-Regular,Consolas,monospace;background:#edf3f8;padding:2px 5px;border-radius:3px;overflow-wrap:anywhere}
pre{background:#102b44;color:#e2f2ff;padding:22px;overflow:auto;line-height:1.65;border-left:4px solid #39baf4;border-radius:4px}pre code{background:none;padding:0;color:inherit;white-space:pre;overflow-wrap:normal}
footer{color:var(--muted);padding:30px 0;font-size:13px}dialog{max-width:96vw;max-height:96vh;padding:8px;border:0;border-radius:8px;background:white}dialog::backdrop{background:#04192fdd}dialog img{max-height:88vh;width:auto;max-width:92vw;margin:0;box-shadow:none;cursor:zoom-out}
@media(max-width:1050px){.layout{grid-template-columns:1fr;gap:18px}nav{position:static;max-height:220px}main{padding:24px}h1{font-size:27px}h2{font-size:23px}}
@media print{header,nav,dialog{display:none}.layout{display:block;padding:0}main{border:0;padding:0}h2{break-before:auto}pre{white-space:pre-wrap}a{color:inherit}img,table{break-inside:avoid}}
</style></head><body>
<header><small>CLAIMSURE ACADEMY · HANDS-ON TUTORIAL</small><div>Data API + Authentication: เรียก API แล้วเห็นข้อมูลตามสิทธิ์</div></header>
<div class="layout"><nav aria-label="สารบัญ"><strong>ทำตามทีละขั้น</strong>${nav}<footer><a href="API-LAB.md">Markdown Source</a><br><a href="README.md">Studio / หัวข้อเสริม</a><br><a href="verification.json">API Verification</a></footer></nav><main>${content}</main></div>
<dialog aria-label="ภาพหน้าจอขนาดเต็ม"><img alt=""></dialog>
<script>
for(const table of document.querySelectorAll('table')){const wrapper=document.createElement('div');wrapper.className='table-scroll';table.replaceWith(wrapper);wrapper.append(table)}
const dialog=document.querySelector('dialog');for(const image of document.querySelectorAll('main img')){image.tabIndex=0;const show=()=>{const large=dialog.querySelector('img');large.src=image.src;large.alt=image.alt;dialog.showModal()};image.addEventListener('click',show);image.addEventListener('keydown',event=>{if(event.key==='Enter')show()})}dialog.addEventListener('click',()=>dialog.close());
</script></body></html>`)
console.log('Rendered docs/tutorials/supabase-self-hosted/index.html')
