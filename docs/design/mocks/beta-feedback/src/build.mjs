// Mock-ups for the beta-tester feedback design (ADR 0023). Same look as docs/design/mocks/2026-10-09 (themes,
// gummy button A, OpenDyslexic captions, retro text buttons). Mock-ups only: nothing here ships in the app.
// Run: node build.mjs   (uses playwright-core from ~/.agents/dashboard/node_modules)
import fs from 'node:fs'
import path from 'node:path'
import { createRequire } from 'node:module'

const require = createRequire(path.join(process.env.HOME, '.agents/dashboard/node_modules/'))
const { chromium } = require('playwright-core')
const SRC = import.meta.dirname
const OUT = path.resolve(SRC, '..')

const T = {
  paper: { name: 'Paper', kind: 'light', bg: '#FAF5E6', text: '#141419', gear: '#14514B', s1: '#14514B', s2: '#7A350C', green: '#12512F', card: '#FFFFFF', line: '#E4DCCB', muted: '#5C6A68' },
  night: { name: 'Night', kind: 'dark', bg: '#1D2536', text: '#E9E3D5', gear: '#C9D6F2', s1: '#93DCD1', s2: '#F2C994', green: '#9BE3B4', card: '#283248', line: '#3A465F', muted: '#B9B3A6' },
}
const BRAND = { teal: '#1F998B', deep: '#0F5C55' }

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
body { font-family: -apple-system, BlinkMacSystemFont, 'SF Pro Rounded', 'Helvetica Neue', sans-serif; background: #E9E4DA; color: #1b1b1b; }
.board { padding: 36px; display: flex; flex-direction: column; gap: 22px; }
.board h1 { font-size: 26px; font-weight: 800; color: #0F3F3C; }
.board .sub { font-size: 15px; color: #3d4b4a; max-width: 1150px; line-height: 1.45; }
.row { display: flex; gap: 32px; align-items: flex-start; flex-wrap: wrap; }
.cap { font-size: 14px; color: #2a3534; margin-top: 10px; max-width: 402px; line-height: 1.4; }
.cap b { color: #0F3F3C; }
.phone { position: relative; width: 402px; height: 874px; border-radius: 54px; overflow: hidden; box-shadow: 0 0 0 10px #1b1d1f, 0 18px 40px rgba(0,0,0,.25); flex: none; }
.island { position: absolute; top: 11px; left: 50%; width: 124px; height: 36px; transform: translateX(-50%); background: #000; border-radius: 20px; z-index: 90; }
.statusbar { position: absolute; top: 18px; left: 34px; right: 30px; display: flex; justify-content: space-between; font-weight: 600; font-size: 16px; z-index: 80; }
.screen { position: absolute; inset: 0; padding: 62px 20px 34px; }
.topbar { position: relative; height: 64px; display: flex; align-items: center; justify-content: center; }
.gear { position: absolute; left: 0; top: 50%; transform: translateY(-50%); width: 44px; height: 44px; display: grid; place-items: center; }
.status { position: absolute; left: 0; right: 0; top: 62px; height: 64px; font-size: 15px; font-weight: 600; opacity: .75; display: flex; justify-content: center; align-items: center; }
.captions { font-family: 'OpenDyslexic', sans-serif; font-size: 22px; line-height: 1.5; margin-top: 18px; display: flex; flex-direction: column; gap: 16px; }
.spk { font-family: system-ui, sans-serif; font-size: 14px; font-weight: 800; margin-bottom: 1px; }
.btn { border: none; font-weight: 800; letter-spacing: .03em; display: inline-flex; align-items: center; justify-content: center; }
.dim { position: absolute; inset: 0; z-index: 10; }
.card { position: absolute; left: 18px; right: 18px; z-index: 30; border-radius: 28px; padding: 24px 20px 20px; box-shadow: 0 10px 30px rgba(0,0,0,.18); }
.q { font-size: 21px; font-weight: 800; line-height: 1.3; text-align: center; }
.scale { display: grid; grid-template-columns: repeat(10, 1fr); gap: 5px; margin-top: 18px; }
.num { height: 44px; border-radius: 14px; display: grid; place-items: center; font-size: 17px; font-weight: 800; }
.ends { display: flex; justify-content: space-between; font-size: 13px; font-weight: 700; margin-top: 8px; }
.links { display: flex; justify-content: space-between; margin-top: 18px; font-size: 17px; font-weight: 700; }
.sheet { position: absolute; left: 0; right: 0; bottom: 0; top: 70px; border-radius: 26px 26px 0 0; z-index: 40; padding: 22px 22px; overflow: hidden; }
.sec { font-size: 13px; font-weight: 800; letter-spacing: .04em; text-transform: none; margin: 18px 0 8px; opacity: .75; }
.rowline { display: flex; justify-content: space-between; align-items: center; font-size: 17px; padding: 6px 0; }
.hr { height: 1px; margin: 12px 0; }
.pill { font-size: 12px; font-weight: 800; padding: 3px 9px; border-radius: 10px; }
.kb { position: absolute; left: 0; right: 0; bottom: 0; height: 290px; z-index: 50; background: #D1D4DA; display: grid; grid-template-rows: repeat(4, 1fr); padding: 8px 4px 40px; gap: 8px; }
.kb .r { display: flex; gap: 5px; justify-content: center; }
.kb .k { width: 33px; background: #fff; border-radius: 6px; box-shadow: 0 1px 0 #898a8d; display: grid; place-items: center; font-size: 20px; color: #000; }
.anno { position: absolute; z-index: 95; font-size: 13px; font-weight: 700; background: #FFF6D8; color: #5b3a00; border: 2px solid #E0A400; border-radius: 10px; padding: 6px 10px; max-width: 210px; line-height: 1.3; }
`
const GEAR = (c, s = 30) => `<svg width="${s}" height="${s}" viewBox="0 0 24 24" fill="none" stroke="${c}" stroke-width="2.1" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="3.2"/><path d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 1 1-2.83 2.83l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 1 1-4 0v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 1 1-2.83-2.83l.06-.06A1.65 1.65 0 0 0 4.68 15a1.65 1.65 0 0 0-1.51-1H3a2 2 0 1 1 0-4h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 1 1 2.83-2.83l.06.06A1.65 1.65 0 0 0 9 4.68a1.65 1.65 0 0 0 1-1.51V3a2 2 0 1 1 4 0v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 1 1 2.83 2.83l-.06.06A1.65 1.65 0 0 0 19.4 9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 1 1 0 4h-.09a1.65 1.65 0 0 0-1.51 1z"/></svg>`

const LINES = [
  { s: 1, t: "So we finally tried the new place on Fifth, Luigi's." },
  { s: 2, t: 'Oh, how was it? I heard the pasta is homemade.' },
  { s: 1, t: 'So good. The waiter said they make the ravioli every morning.' },
  { s: 2, t: 'We should take your mom there for her birthday.' },
]
const captions = (t, lines = LINES) => `<div class="captions" style="color:${t.text}">` + lines.map((l) => `<div><div class="spk" style="color:${l.s === 1 ? t.s1 : t.s2}">Speaker ${l.s}</div>${l.t}</div>`).join('') + `</div>`
const phone = (t, inner) => `<div class="phone" style="background:${t.bg}"><div class="island"></div><div class="statusbar" style="color:${t.text}"><span>9:41</span><span>●●●● ▮</span></div><div class="screen">${inner}</div></div>`
const topbar = (t, status = '') => `<div class="topbar"><div class="gear">${GEAR(t.gear)}</div></div>` + (status ? `<div class="status" style="color:${t.text}">${status}</div>` : '')
const startBtn = (t) => `<div class="btn" style="position:absolute;left:20px;right:20px;bottom:40px;height:60px;border-radius:30px;font-size:21px;z-index:30;${primary(t)}">Start captions</div>`
const RETRO = "font-family:'SF Mono',Menlo,ui-monospace,monospace;font-weight:700;font-size:26px;white-space:pre"
const anno = (style, text) => `<div class="anno" style="${style}">${text}</div>`

// The rating card. `picked` highlights one number; `note` opens the note field.
function ratingCard(t, { picked = null, note = false, top = 250 } = {}) {
  const nums = Array.from({ length: 10 }, (_, i) => i + 1).map((n) => {
    const on = n === picked
    const style = on ? `${primary(t)}` : `background:${t.kind === 'light' ? '#F1EBDD' : '#334057'};color:${t.text};box-shadow:0 2px 0 ${t.kind === 'light' ? '#D9CFBC' : '#1A2131'};`
    return `<div class="num" style="${style}">${n}</div>`
  }).join('')
  const noteHTML = note
    ? `<div style="margin-top:16px;border-radius:16px;padding:12px 14px;min-height:76px;font-size:17px;line-height:1.35;background:${t.kind === 'light' ? '#F6F1E6' : '#202939'};color:${t.text}">Lost it when the waiter talked fast<span style="display:inline-block;width:2px;height:20px;background:${BRAND.teal};vertical-align:middle;margin-left:2px"></span></div>
       <div style="display:flex;justify-content:flex-end;margin-top:12px"><div class="btn" style="height:44px;padding:0 24px;border-radius:22px;font-size:17px;${primary(t)}">Done</div></div>`
    : `<div class="links"><span style="color:${t.gear}">Add a note</span><span style="color:${t.muted}">Skip</span></div>`
  return `<div class="card" style="top:${top}px;background:${t.card};color:${t.text}">
    <div class="q">How well could you follow the conversation?</div>
    <div class="scale">${nums}</div>
    <div class="ends" style="color:${t.muted}"><span>Not at all</span><span>Every word</span></div>
    ${noteHTML}</div>`
}
// After [ New ]: the conversation fades out and the card appears over the fresh, empty main screen.
function afterNew(t, opts = {}) {
  const dimmed = `<div class="dim" style="background:${t.bg};opacity:.9"></div>`
  return phone(t, topbar(t, 'Paused') + captions(t) + dimmed + ratingCard(t, opts) + (opts.note ? '' : startBtn(t)))
}

function settingsBeta(t) {
  const row = (label, right = '', color = t.text) => `<div class="rowline"><span style="color:${color}">${label}</span><span style="color:${t.muted}">${right}</span></div>`
  const hr = `<div class="hr" style="background:${t.line}"></div>`
  return phone(t, `<div style="display:flex;justify-content:space-between;align-items:center;margin-top:6px"><div style="font-size:30px;font-weight:800;color:${t.text}">Settings</div><div style="font-size:18px;font-weight:700;color:${t.gear}">Done</div></div>
    <div class="sec" style="color:${t.text}">Stop when it's quiet</div>
    <div style="display:flex;gap:8px">${['5 min', '15 min', '30 min', 'Never'].map((x, i) => `<div style="padding:10px 16px;border-radius:20px;font-weight:700;font-size:16px;${i === 0 ? primary(t) : `background:${t.kind === 'light' ? '#EEE6D6' : '#2E384D'};color:${t.text}`}">${x}</div>`).join('')}</div>
    ${hr}<div class="sec" style="color:${t.text}">Saved</div>${row('Saved conversations', '3 ›')}<div style="font-size:14px;color:${t.muted}">Saved conversations are deleted after 30 days.</div>
    ${hr}<div class="sec" style="color:${t.text};display:flex;gap:8px;align-items:center">Test version <span class="pill" style="background:${BRAND.teal};color:#fff">TestFlight only</span></div>
    <div class="rowline"><span style="color:${t.gear};font-weight:700">Send feedback to Gil</span><span style="color:${t.muted}">4 conversations ›</span></div>
    <div style="font-size:14px;color:${t.muted};line-height:1.4">Your ratings and notes, plus measurements like lag and battery. Never what anyone said.</div>
    ${hr}<div class="sec" style="color:${t.text}">How to use Seal</div><div class="btn" style="width:100%;height:56px;border-radius:28px;font-size:19px;${primary(t)}">Show how to use Seal</div>
    ${hr}<div class="sec" style="color:${t.text}">About</div>${row('Privacy policy', '', t.gear)}${row('Help and contact', '', t.gear)}`)
}

function preview(t) {
  const c = (title, items) => `<div style="margin-top:12px;padding:12px 14px;border-radius:16px;background:${t.kind === 'light' ? '#F6F1E6' : '#202939'}"><div style="font-weight:800;font-size:16px;margin-bottom:6px">${title}</div>${items.map(([k, v]) => `<div style="display:flex;justify-content:space-between;font-size:15px;padding:2px 0"><span style="color:${t.muted}">${k}</span><span style="font-weight:700">${v}</span></div>`).join('')}</div>`
  return phone(t, topbar(t) + `<div class="sheet" style="background:${t.card};color:${t.text}">
    <div style="display:flex;justify-content:space-between;align-items:center"><span style="font-size:17px;color:${t.gear};font-weight:700">Cancel</span><span style="font-size:18px;font-weight:800">What will be sent</span><span style="width:52px"></span></div>
    <div style="margin-top:14px;font-size:15px;line-height:1.4;color:${t.muted}">4 conversations since your last report. Seal never sends what anyone said, any audio, or names.</div>
    ${c('Sat 12 Oct · 23 min', [['Your rating', '8 / 10'], ['Your note', '“Lost it when the waiter talked fast”'], ['Caption lag', '0.6 s (worst 1.5 s)'], ['Speakers', '3 · labels steady'], ['Battery', '6.5% per 30 min'], ['Ended', 'You pressed Stop']])}
    ${c('Sat 12 Oct · 8 min', [['Your rating', 'Skipped'], ['Caption lag', '0.7 s (worst 1.9 s)'], ['Ended', 'Quiet for 5 min']])}
    ${c('Fri 11 Oct · 41 min', [['Your rating', '6 / 10'], ['Caption lag', '1.1 s (worst 3.2 s)'], ['Phone', 'Got warm (serious)']])}
    <div style="margin-top:10px;font-size:14px;color:${t.muted}">+ 1 more · iPhone 14 · iOS 26.1 · Seal 1.0 (42)</div>
    <div class="btn" style="position:absolute;left:22px;right:22px;bottom:38px;height:58px;border-radius:29px;font-size:19px;${primary(t)}">Continue to Messages</div></div>`)
}

function messages() {
  const blue = '#0A84FF'
  return `<div class="phone" style="background:#F2F2F7"><div class="island"></div><div class="statusbar" style="color:#000"><span>9:41</span><span>●●●● ▮</span></div>
    <div style="position:absolute;top:62px;left:0;right:0;bottom:0;background:#fff;border-radius:22px 22px 0 0;box-shadow:0 -1px 0 #ddd">
      <div style="display:flex;justify-content:space-between;align-items:center;padding:14px 18px;font-size:17px"><span style="color:${blue}">Cancel</span><span style="font-weight:700">New iMessage</span><span style="width:52px"></span></div>
      <div style="padding:10px 18px;border-top:1px solid #e5e5ea;border-bottom:1px solid #e5e5ea;font-size:17px"><span style="color:#8e8e93">To: </span><span style="color:${blue};background:#E5F0FF;padding:3px 8px;border-radius:8px">Gil</span></div>
      <div style="position:absolute;left:12px;right:12px;bottom:330px;border:1px solid #d1d1d6;border-radius:20px;padding:12px;font-size:16px;line-height:1.35;background:#fff">
        <div style="display:flex;gap:12px;align-items:center;background:#F2F2F7;border-radius:14px;padding:10px 12px;margin-bottom:10px">
          <div style="width:40px;height:50px;border-radius:6px;background:#fff;border:1px solid #c7c7cc;display:grid;place-items:center;font-size:11px;font-weight:800;color:${BRAND.deep}">JSON</div>
          <div><div style="font-weight:700;font-size:15px">seal-feedback-42-20261012-1804.json</div><div style="color:#8e8e93;font-size:13px">4 KB</div></div></div>
        Seal beta feedback: 4 conversations, iPhone 14, iOS 26.1, build 42. Ratings 8, skipped, 6, 9. Worst lag 3.2 s.
        <div style="position:absolute;right:10px;bottom:10px;width:30px;height:30px;border-radius:50%;background:${blue};display:grid;place-items:center;color:#fff;font-weight:900">↑</div></div>
      <div class="kb"><div class="r">${'qwertyuiop'.split('').map((k) => `<div class="k">${k}</div>`).join('')}</div><div class="r">${'asdfghjkl'.split('').map((k) => `<div class="k">${k}</div>`).join('')}</div><div class="r">${'zxcvbnm'.split('').map((k) => `<div class="k">${k}</div>`).join('')}</div><div class="r"><div class="k" style="width:300px;font-size:15px">space</div></div></div>
    </div></div>`
}

function notice(t) {
  return phone(t, topbar(t) + startBtn(t) + `<div class="dim" style="background:${t.bg};opacity:.88"></div>
    <div class="card" style="top:200px;background:${t.card};color:${t.text};text-align:center">
      <div class="pill" style="display:inline-block;background:${BRAND.teal};color:#fff">Test version</div>
      <div style="font-size:24px;font-weight:800;margin-top:14px;line-height:1.25">Thanks for testing Seal</div>
      <div style="font-size:17px;line-height:1.45;margin-top:12px;color:${t.text}">After a conversation, Seal asks how it went. It also keeps measurements like caption lag and battery.</div>
      <div style="font-size:17px;line-height:1.45;margin-top:10px;font-weight:800">It never keeps what anyone said.</div>
      <div style="font-size:16px;line-height:1.45;margin-top:10px;color:${t.muted}">You choose when to send them to Gil, from Settings.</div>
      <div class="btn" style="margin-top:20px;width:100%;height:56px;border-radius:28px;font-size:19px;${primary(t)}">Got it</div></div>`)
}

const PAGES = []
const doc = (title, body, w, h) => `<!doctype html><html><head><meta charset="utf-8"><title>${title}</title><style>${CSS}</style></head><body style="width:${w}px;min-height:${h}px">${body}</body></html>`
const board = (title, sub, content) => `<div class="board"><h1>${title}</h1><div class="sub">${sub}</div>${content}</div>`
const fig = (p, cap) => `<div>${p}<div class="cap">${cap}</div></div>`
const add = (file, title, html, w, h) => PAGES.push({ file, title, html: doc(title, html, w, h), w, h })

add('01-rating-card.png', 'Rating card',
  board('1 · After a conversation: the 2-second rating (beta only)', 'When she taps [ New ] (or leaves a paused conversation), a card asks one question with 1 to 10 in a single row. One tap and it fades away. Add a note is optional; Skip records a skip. At most once per conversation, never while captioning. TestFlight installs only; the App Store version never shows it.',
    `<div class="row">${fig(afterNew(T.paper), '<b>Light (Paper).</b> One question, one tap.')}${fig(afterNew(T.paper, { picked: 8 }), '<b>Tapped 8.</b> The number squishes like every gummy button, then the card fades.')}${fig(afterNew(T.night), '<b>Dark (Night).</b> Same card on the dark theme.')}</div>`), 1400, 1000)
add('02-add-a-note.png', 'Add a note',
  board('2 · Add a note (optional)', 'Tapping Add a note opens a small text box in the same card; the keyboard comes up. Done saves the rating and the note together. The note is the only free text a report ever contains.',
    `<div class="row">${fig(phone(T.paper, topbar(T.paper, 'Paused') + captions(T.paper) + `<div class="dim" style="background:${T.paper.bg};opacity:.9"></div>` + ratingCard(T.paper, { picked: 8, note: true, top: 120 }) + `<div class="kb"><div class="r">${'qwertyuiop'.split('').map((k) => `<div class="k">${k}</div>`).join('')}</div><div class="r">${'asdfghjkl'.split('').map((k) => `<div class="k">${k}</div>`).join('')}</div><div class="r">${'zxcvbnm'.split('').map((k) => `<div class="k">${k}</div>`).join('')}</div><div class="r"><div class="k" style="width:300px;font-size:15px">space</div></div></div>`), '<b>Note open.</b> Typed by the tester; nothing from the conversation is filled in.')}</div>`), 520, 1000)
add('03-settings-send-feedback.png', 'Settings: Send feedback to Gil',
  board('3 · Settings: Send feedback to Gil (TestFlight only)', 'A "Test version" section appears only in TestFlight installs, between Saved and How to use Seal, in the borderless Settings style from #105. It says how many conversations are waiting and, in plain words, what is and isn\'t included.',
    `<div class="row">${fig(settingsBeta(T.paper), '<b>Light.</b> The row shows how many conversations are waiting.')}${fig(settingsBeta(T.night), '<b>Dark.</b>')}</div>`), 1000, 1000)
add('04-preview.png', 'Preview of what will be sent',
  board('4 · Exactly what will be sent', 'Before anything leaves the phone, a plain preview lists every conversation in the report, in words rather than code. Continue to Messages opens the text; Cancel sends nothing.',
    `<div class="row">${fig(preview(T.paper), '<b>Light.</b> Ratings, notes and measurements, newest first.')}${fig(preview(T.night), '<b>Dark.</b>')}</div>`), 1000, 1000)
add('05-messages.png', 'Messages with the report attached',
  board('5 · Apple Messages, already addressed to Gil', 'Apple\'s own Messages sheet opens with Gil as the recipient, the report attached as a small file and a one-line summary typed in. The tester taps send (or Cancel). After it sends, those records are deleted from the phone. If Messages can\'t send, the share sheet opens instead.',
    `<div class="row">${fig(messages(), '<b>Messages.</b> Drawn like iOS Messages; the real sheet is Apple\'s.')}</div>`), 520, 1000)
add('06-beta-notice.png', 'One-time beta notice',
  board('6 · First launch of the test version: one notice', 'Shown once, after the launch animation, on the first launch of a TestFlight build. One button. The same words go in TestFlight\'s "What to Test".',
    `<div class="row">${fig(notice(T.paper), '<b>Light.</b>')}${fig(notice(T.night), '<b>Dark.</b>')}</div>`), 1000, 1000)

const CANDIDATES = [
  path.join(process.env.HOME, 'Library/Caches/ms-playwright/chromium-1228/chrome-mac-arm64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing'),
  '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
]
const browser = await chromium.launch({ executablePath: CANDIDATES.find((p) => fs.existsSync(p)) })
const page = await browser.newPage({ deviceScaleFactor: 3, viewport: { width: 1400, height: 1000 } })
for (const p of PAGES) {
  const htmlPath = path.join(SRC, p.file.replace('.png', '.html'))
  fs.writeFileSync(htmlPath, p.html)
  await page.setViewportSize({ width: p.w, height: p.h })
  await page.goto('file://' + htmlPath)
  await page.evaluate(() => document.fonts.ready)
  await page.waitForTimeout(250)
  await page.screenshot({ path: path.join(OUT, p.file), fullPage: true })
  console.log('rendered', p.file)
}
await browser.close()
