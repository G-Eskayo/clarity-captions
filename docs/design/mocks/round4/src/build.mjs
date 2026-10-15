// Round-4 mock-ups (2026-10-15): changes from TestFlight build 3 feedback (docs/use-cases.md). Helpers copied from
// ../../round3/src/build.mjs. Mock-ups only: nothing here ships.
// Run: node build.mjs
import fs from 'node:fs'
import path from 'node:path'
import { execFileSync } from 'node:child_process'
import { createRequire } from 'node:module'

const require = createRequire(path.join(process.env.HOME, '.agents/dashboard/node_modules/'))
const { chromium } = require('playwright-core')
const SRC = import.meta.dirname
const OUT = path.resolve(SRC, '..')

const T = {
  paper: { name: 'Paper', bg: '#FAF5E6', text: '#141419', gear: '#14514B', s1: '#14514B', s2: '#7A350C', green: '#12512F', line: '#E4DCCB', muted: '#5C6A68' },
  night: { name: 'Night', bg: '#1D2536', text: '#E9E3D5', gear: '#C9D6F2', s1: '#93DCD1', s2: '#F2C994', green: '#9BE3B4', line: '#3A465F', muted: '#B9B3A6' },
}
const TEAL = '#1F998B'
function lum(hex) {
  const [r, g, b] = hex.replace('#', '').match(/../g).map((h) => parseInt(h, 16) / 255).map((v) => (v <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4))
  return 0.2126 * r + 0.7152 * g + 0.0722 * b
}
function lip(hex, amt = 0.28) {
  const dark = lum(hex) < 0.25
  return '#' + hex.replace('#', '').match(/../g).map((h) => parseInt(h, 16)).map((v) => Math.round(dark ? v + (255 - v) * amt : v * (1 - amt))).map((v) => v.toString(16).padStart(2, '0')).join('')
}
const primary = (t) => `background:${t.text};color:${t.bg};box-shadow:0 3px 0 ${lip(t.text)};`

const CSS = `
@font-face { font-family: 'OpenDyslexic'; src: url('../../2026-10-09/src/fonts/OpenDyslexic-Regular.woff') format('woff'); font-weight: 400; }
@font-face { font-family: 'OpenDyslexic'; src: url('../../2026-10-09/src/fonts/OpenDyslexic-Bold.woff') format('woff'); font-weight: 700; }
* { box-sizing: border-box; margin: 0; padding: 0; }
body { font-family: -apple-system, BlinkMacSystemFont, 'Helvetica Neue', sans-serif; background: #E9E4DA; color: #1b1b1b; }
.board { padding: 36px; display: flex; flex-direction: column; gap: 22px; }
.board h1 { font-size: 26px; font-weight: 800; color: #0F3F3C; }
.board .sub { font-size: 15px; color: #3d4b4a; max-width: 1250px; line-height: 1.45; }
.row { display: flex; gap: 28px; align-items: flex-start; flex-wrap: wrap; }
.cap { font-size: 14px; color: #2a3534; margin-top: 10px; max-width: 402px; line-height: 1.4; }
.cap b { color: #0F3F3C; }
.phone { position: relative; width: 402px; height: 874px; border-radius: 54px; overflow: hidden; box-shadow: 0 0 0 10px #1b1d1f, 0 18px 40px rgba(0,0,0,.25); flex: none; }
.island { position: absolute; top: 11px; left: 50%; width: 124px; height: 36px; transform: translateX(-50%); background: #000; border-radius: 20px; z-index: 90; }
.statusbar { position: absolute; top: 18px; left: 34px; right: 30px; display: flex; justify-content: space-between; font-weight: 600; font-size: 16px; z-index: 80; }
.layer { position: absolute; inset: 0; padding: 62px 20px 34px; }
.topbar { position: relative; height: 64px; display: flex; align-items: center; justify-content: center; font-size: 15px; font-weight: 600; }
.gear { position: absolute; left: 0; top: 50%; transform: translateY(-50%); width: 44px; height: 44px; display: grid; place-items: center; }
.captions { font-family: 'OpenDyslexic', sans-serif; font-size: 22px; line-height: 1.5; margin-top: 10px; display: flex; flex-direction: column; gap: 16px; }
.spk { font-family: system-ui, sans-serif; font-size: 14px; font-weight: 800; margin-bottom: 1px; }
.btn { border: none; font-weight: 800; letter-spacing: .03em; display: inline-flex; align-items: center; justify-content: center; }
.retro { font-family: 'SF Mono', Menlo, ui-monospace, monospace; font-weight: 700; font-size: 26px; white-space: pre; }
.say { font-size: 20px; font-weight: 800; line-height: 1.3; }
.small { font-size: 16px; line-height: 1.45; }
.sec { font-size: 13px; font-weight: 800; letter-spacing: .04em; margin: 16px 0 8px; opacity: .7; }
.rule { height: 1px; margin: 10px 0; }
.tag { position: absolute; z-index: 95; font-size: 13px; font-weight: 700; background: #FFF6D8; color: #5b3a00; border: 2px solid #E0A400; border-radius: 10px; padding: 6px 10px; max-width: 220px; line-height: 1.3; }
.frame-no { font-size: 13px; font-weight: 800; color: #0F3F3C; margin-bottom: 6px; }
`
const GEAR = (c, s = 30) => `<svg width="${s}" height="${s}" viewBox="0 0 24 24" fill="none" stroke="${c}" stroke-width="2.1" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="3.2"/><path d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 1 1-2.83 2.83l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 1 1-4 0v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 1 1-2.83-2.83l.06-.06A1.65 1.65 0 0 0 4.68 15a1.65 1.65 0 0 0-1.51-1H3a2 2 0 1 1 0-4h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 1 1 2.83-2.83l.06.06A1.65 1.65 0 0 0 9 4.68a1.65 1.65 0 0 0 1-1.51V3a2 2 0 1 1 4 0v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 1 1 2.83 2.83l-.06.06A1.65 1.65 0 0 0 19.4 9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 1 1 0 4h-.09a1.65 1.65 0 0 0-1.51 1z"/></svg>`
const LINES = [
  { s: 1, t: "So we finally tried the new place on Fifth, Luigi's." },
  { s: 2, t: 'Oh, how was it? I heard the pasta is homemade.' },
  { s: 1, t: 'So good. The waiter said they make the ravioli every morning.' },
  { s: 2, t: 'We should take your mom there for her birthday.' },
]
const captions = (t, lines = LINES, opacity = 1) => `<div class="captions" style="color:${t.text};opacity:${opacity}">` + lines.map((l) => `<div><div class="spk" style="color:${l.s === 1 ? t.s1 : t.s2}">${l.name ?? 'Speaker ' + l.s}</div>${l.t}</div>`).join('') + `</div>`
const phone = (t, inner) => `<div class="phone" style="background:${t.bg}"><div class="island"></div><div class="statusbar" style="color:${t.text}"><span>9:41</span><span>●●●● ▮</span></div>${inner}</div>`
const topbar = (t, status = '', gear = true) => `<div class="topbar" style="color:${t.text}">${gear ? `<div class="gear">${GEAR(t.gear)}</div>` : ''}<span style="opacity:.75">${status}</span></div>`
const startBtn = (t, label = 'Start captions', extra = '') => `<div class="btn" style="position:absolute;left:20px;right:20px;bottom:40px;height:64px;border-radius:32px;font-size:21px;z-index:30;${primary(t)}${extra}">${label}</div>`
const stopDot = () => `<div style="position:absolute;right:24px;bottom:44px;width:58px;height:58px;border-radius:29px;background:#C62828;color:#fff;display:grid;place-items:center;font-size:26px;font-weight:800;z-index:30">✕</div>`
const veil = (t, o = 0.86) => `<div style="position:absolute;inset:0;background:${t.bg};opacity:${o};z-index:10"></div>`
const retro = (t, word, color, extra = '') => `<div class="retro" style="color:${color ?? t.text};${extra}">[ ${word} ]</div>`
const tag = (style, text) => `<div class="tag" style="${style}">${text}</div>`
const layer = (inner, style = '') => `<div class="layer" style="${style}">${inner}</div>`

// --- Board helpers (as in round 2) ---------------------------------------------------------------------------
const PAGES = []
const doc = (title, body, w, h) => `<!doctype html><html><head><meta charset="utf-8"><title>${title}</title><style>${CSS}</style></head><body style="width:${w}px;min-height:${h}px">${body}</body></html>`
const board = (title, sub, content) => `<div class="board"><h1>${title}</h1><div class="sub">${sub}</div>${content}</div>`
const fig = (p, cap, no = '') => `<div>${no ? `<div class="frame-no">${no}</div>` : ''}${p}<div class="cap">${cap}</div></div>`
const add = (file, title, html, w, h) => PAGES.push({ file, title, html: doc(title, html, w, h), w, h })
const ANIMS = []
const animDoc = (body, script) => `<!doctype html><html><head><meta charset="utf-8"><style>${CSS} body{background:#E9E4DA;padding:20px;width:462px;height:934px}</style></head><body>${body}<script>${script}</script></body></html>`
const ease = `const ease=(x)=>x<0?0:x>1?1:x<.5?4*x*x*x:1-Math.pow(-2*x+2,3)/2; const seg=(t,a,b)=>ease((t-a)/(b-a));`


// --- Round 4 (2026-10-15): TestFlight build 3 feedback -------------------------------------------------------
const NEXT = (t) => `<div style="margin-top:22px;display:grid;place-items:center">${retro(t, 'Next ›')}</div>`
const STEPS4 = 4
function step4(t, o) {
  const { step, status = 'Ready', title, sub, top = 560, hole = null, start = true, stop = false, mid = '', body = '', button = 'next' } = o
  const veilCut = hole
    ? `<div style="position:absolute;z-index:15;left:${hole[0]}px;top:${hole[1]}px;width:${hole[2]}px;height:${hole[3]}px;border-radius:${hole[4] ?? 32}px;box-shadow:0 0 0 2000px ${t.bg}E6"></div>`
    : `<div style="position:absolute;inset:0;background:${t.bg};opacity:.9;z-index:15"></div>`
  return phone(t, layer(topbar(t, status) + body) + veilCut +
    `<div style="position:absolute;right:22px;top:72px;z-index:25;color:${t.text};font-size:15px;font-weight:700;opacity:.8">Skip tour</div>` +
    `<div style="position:absolute;left:28px;right:28px;top:${top - 34}px;z-index:25;color:${t.text};text-align:center;font-size:14px;font-weight:700;opacity:.55">${step} of ${STEPS4}${step > 1 ? ' · ‹ Back' : ''}</div>` +
    `<div style="position:absolute;left:28px;right:28px;top:${top}px;z-index:25;color:${t.text};text-align:center"><div class="say">${title}</div><div class="small" style="opacity:.82;margin-top:6px">${sub}</div>${button === 'next' ? NEXT(t) : `<div style="margin-top:22px;display:grid;place-items:center">${retro(t, 'Done')}</div>`}</div>` +
    (mid ? `<div style="position:absolute;left:0;right:0;top:330px;z-index:20;display:flex;flex-direction:column;align-items:center;gap:22px">${mid}</div>` : '') +
    (start ? startBtn(t) : '') + (stop ? stopDot() : ''))
}
const twoVoices = (t) => `<div class="captions" style="color:${t.text}"><div><div class="spk" style="color:${t.s1}">Speaker 1</div>Hi, is this working? I can see what I'm saying.</div><div><div class="spk" style="color:${t.s2}">Speaker 2</div>Yep, it put me on my own line.</div></div>`
const TOUR4 = (t) => [
  { n: '1 of 4', cap: 'Start is lit. Tapping Start <b>or</b> [ Next ] moves on. Nothing on a timer.', f: step4(t, { step: 1, title: 'Set the phone flat on the table.', sub: "Between you and whoever's talking. Then tap Start captions.", hole: [16, 790, 370, 72, 36] }) },
  { n: '2 of 4', cap: 'Her words (or, if she tapped Next without starting, a short example). Stays until she taps [ Next ].', f: step4(t, { step: 2, status: 'Listening', title: 'Words show up here as people talk.', sub: "A new voice gets its own line. Seal goes by the sound of the voice, so it can mix people up. Scroll up any time to reread.", top: 400, start: false, stop: true, body: twoVoices(t), hole: [16, 130, 370, 230, 20] }) },
  { n: '3 of 4', cap: 'Shows the pause screen with both buttons, so nothing has to be "found". Tapping ✕ or [ Next ] moves on. Old steps 3-6 (✕, Save, tap the dim, hold) become this one.', f: step4(t, { step: 3, status: 'Paused', title: 'Tap ✕ to pause.', sub: '[ Save ] keeps the conversation on this phone for 30 days. [ New ] starts a clean page.', body: twoVoices(t), mid: retro(t, 'Save') + retro(t, 'New'), top: 560, start: false }) },
  { n: '4 of 4', cap: 'Last page: the gear and where saved conversations are (depends on the placement picked below). No "go into Settings" step. [ Done ] ends it.', f: step4(t, { step: 4, status: 'Paused', title: "That's it.", sub: 'The gear has colors, text size and lettering.<br><br>You can replay this in Settings.', top: 440, body: twoVoices(t), hole: [16, 66, 52, 52, 26], button: 'done' }) },
]
add('01-tour-v3-four-steps.png', 'Tour v3: four steps you control',
  board('1 · Tour v3: four steps, you control it (Paper)', 'From your TestFlight notes: show it all, let the user decide when to move on, don\'t explain the obvious, don\'t add pages. 8 steps become 4. Every step has [ Next ›] <b>and</b> also moves on when you do the real thing. Nothing disappears on a timer. Back and Skip tour stay. Copy, quiet-pause and hold-to-copy are no longer explained.',
    `<div class="row">${TOUR4(T.paper).map((s) => fig(s.f, s.cap, s.n)).join('')}</div>`), 1900, 1060)

// --- Saved conversations: three placements -------------------------------------------------------------------
const STACK = (c, s = 28) => `<svg width="${s}" height="${s}" viewBox="0 0 24 24" fill="none" stroke="${c}" stroke-width="2.1" stroke-linecap="round" stroke-linejoin="round"><path d="M4 7h16M4 12h16M4 17h10"/></svg>`
const idle = (t, inner = '') => phone(t, layer(topbar(t, 'Ready') + captions(t, LINES.slice(0, 2), 0.35)) + inner + startBtn(t))
const savedA = (t) => phone(t, layer(topbar(t, 'Ready') + captions(t, LINES.slice(0, 2), 0.35)) + `<div style="position:absolute;right:20px;top:70px;z-index:30;width:44px;height:44px;display:grid;place-items:center">${STACK(t.gear)}</div>` + startBtn(t))
const savedB = (t) => phone(t, layer(topbar(t, 'Paused') + captions(t, LINES)) + veil(t) + `<div style="position:absolute;left:0;right:0;top:300px;z-index:20;display:flex;flex-direction:column;align-items:center;gap:22px">${retro(t, 'Save')}${retro(t, 'New')}<div style="margin-top:18px;color:${t.gear};font-size:17px;font-weight:700">Saved conversations (3) ›</div></div>` + startBtn(t, 'Start again'))
const savedC = (t) => idle(t, `<div style="position:absolute;left:0;right:0;bottom:122px;z-index:30;display:grid;place-items:center">${retro(t, 'Saved (3)', t.gear, 'font-size:21px')}</div>`)
add('02-saved-placement.png', 'Saved conversations: where it lives',
  board('2 · Saved conversations: three places to pick from', 'From your notes: "isn\'t obvious… could be used a lot. Maybe rethink its location." Today it\'s only inside Settings. Each option keeps it in Settings too.',
    `<div class="row">${fig(savedA(T.paper), '<b>A · Top right, on the main screen.</b> A small list icon opposite the gear, always there. Most visible; adds a second icon to the top bar.', 'A')}${fig(savedB(T.paper), '<b>B · On the pause screen.</b> Under [ Save ] / [ New ], right where you just saved. Nothing new on the main screen; only seen when paused.', 'B')}${fig(savedC(T.paper), '<b>C · Above Start, when not captioning.</b> Retro words like [ Save ]. Visible whenever you\'re about to start; hidden while captioning.', 'C')}${fig(savedA(T.night), 'A on Night.', 'A, dark')}</div>`), 1900, 1060)

// --- Settings preview and Speaker 1 padding ------------------------------------------------------------------
const settingsTop = (t, labelled) => phone(t, layer(`<div class="topbar" style="color:${t.text}"><div class="gear">${GEAR(t.gear)}</div><span style="font-size:20px;font-weight:800">Settings</span></div>
  <div style="color:${t.text}">
    ${labelled ? `<div class="sec">HOW YOUR CAPTIONS WILL LOOK</div><div style="border-radius:16px;padding:14px 16px;background:${t.line}55"><div class="spk" style="color:${t.s1}">Speaker 1</div><div style="font-family:OpenDyslexic;font-size:22px;line-height:1.5">Let's book a table for seven.</div></div>` : `<div style="font-size:22px;line-height:1.4">Preview: Let's book a table for seven.</div>`}
    <div class="sec" style="margin-top:22px">COLORS</div>
    <div style="display:flex;gap:8px">${['#FAF5E6','#DCEFEA','#FBE8D2','#2B2D31','#1D2536','#173331'].map((c,i)=>`<div style="width:46px;height:46px;border-radius:12px;background:${c};border:1px solid ${t.line};display:grid;place-items:center;font-weight:800;color:${i>2?'#ECE6D9':'#141419'}">Aa</div>`).join('')}</div>
  </div>`))
const pad = (t, fixed) => phone(t, layer(topbar(t, 'Listening') + `<div style="position:absolute;left:0;right:0;top:118px;height:${fixed ? 0 : 36}px;background:linear-gradient(${t.bg},${t.bg}00);z-index:5"></div>` + `<div style="margin-top:${fixed ? 26 : 0}px">${captions(t, [LINES[0]])}</div>`) + stopDot())
add('03-preview-and-padding.png', 'Settings preview label and Speaker 1 padding',
  board('3 · The Settings preview, and Speaker 1\'s spacing', 'Preview: "What the heck is that preview at the top?" It\'s a live sample of how your captions will look; say so, and draw it like a caption. Padding: "Speaker 1 needs top padding. It\'s in the scroll fade."',
    `<div class="row">${fig(settingsTop(T.paper, false), 'Today: an unexplained line.', 'Preview, before')}${fig(settingsTop(T.paper, true), 'Proposed: a heading and a caption-style sample, in your chosen colors, size and lettering.', 'Preview, after')}${fig(pad(T.paper, false), 'Today: "Speaker 1" sits inside the top fade.', 'Padding, before')}${fig(pad(T.paper, true), 'Proposed: the first line starts below the fade.', 'Padding, after')}</div>`), 1900, 1060)
// --- Render ---------------------------------------------------------------------------------------------------
const CANDIDATES = [
  path.join(process.env.HOME, 'Library/Caches/ms-playwright/chromium-1228/chrome-mac-arm64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing'),
  '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
]
const browser = await chromium.launch({ executablePath: CANDIDATES.find((x) => fs.existsSync(x)) })
const page = await browser.newPage({ deviceScaleFactor: 2, viewport: { width: 1400, height: 1000 } })
for (const pg of PAGES) {
  const htmlPath = path.join(SRC, pg.file.replace('.png', '.html'))
  fs.writeFileSync(htmlPath, pg.html)
  await page.setViewportSize({ width: pg.w, height: pg.h })
  await page.goto('file://' + htmlPath)
  await page.evaluate(() => document.fonts.ready)
  await page.waitForTimeout(250)
  await page.screenshot({ path: path.join(OUT, pg.file), fullPage: true })
  console.log('rendered', pg.file)
}
await browser.close()
