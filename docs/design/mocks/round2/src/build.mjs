// Round-2 mock-ups (2026-10-10): one screen, fades only, no boxes or borders, an action-driven tour, a smoother
// launch hand-off. Same look as docs/design/mocks/2026-10-09 (themes, gummy button A, OpenDyslexic captions, retro
// text buttons). Mock-ups only: nothing here ships in the app.
// Run: node build.mjs   (uses playwright-core from ~/.agents/dashboard/node_modules and ffmpeg for the GIFs)
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
const SEAL = './seal-nobg.svg'   // design/mascot/seal-rig.svg without the icon's square
const SEAL_TEAL = './seal-nobg-teal-rays.svg'   // the same, rays in teal so they show on light themes

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

// --- Settings, borderless, as a full screen on the same background (no sheet) -----------------------------
function settingsScreen(t, { back = 'gear' } = {}) {
  const top = back === 'gear'
    ? `<div class="topbar" style="color:${t.text}"><div class="gear" style="background:${t.text}14;border-radius:22px">${GEAR(t.gear)}</div><span style="font-size:20px;font-weight:800">Settings</span></div>`
    : `<div class="topbar" style="color:${t.text}"><div style="position:absolute;left:0;font-size:17px;font-weight:700;color:${t.gear}">‹ Captions</div><span style="font-size:20px;font-weight:800">Settings</span></div>`
  const sw = ['#FAF5E6', '#DDEFEA', '#F8E1CC', '#2B2D31', '#1D2536', '#173331']
  return top + `<div style="color:${t.text};margin-top:8px">
    <div style="font-family:OpenDyslexic;font-size:22px;line-height:1.5">Preview: Let's book a table for seven.</div>
    <div class="sec">Colors</div>
    <div style="display:flex;gap:10px">${sw.map((c, i) => `<div style="text-align:center"><div style="width:48px;height:48px;border-radius:14px;background:${c};display:grid;place-items:center;font-weight:800;color:${i < 3 ? '#141419' : '#E9E3D5'};${i === 0 ? `outline:0` : ''}">Aa</div>${i === (t.name === 'Night' ? 4 : 0) ? `<div style="color:${t.gear};font-weight:800">✓</div>` : ''}</div>`).join('')}</div>
    <div class="rule" style="background:${t.line}"></div>
    <div class="sec">Size</div>
    <div style="display:flex;gap:12px"><div class="btn" style="flex:1;height:52px;border-radius:26px;font-size:20px;background:${t.line};color:${t.text}">A−</div><div class="btn" style="flex:1;height:52px;border-radius:26px;font-size:20px;background:${t.line};color:${t.text}">A+</div></div>
    <div class="rule" style="background:${t.line}"></div>
    <div class="sec">Lettering</div>
    <div class="small" style="line-height:2"><span style="font-family:OpenDyslexic">OpenDyslexic</span> <span style="color:${t.gear}">✓</span><br>Atkinson Hyperlegible<br>Standard<br>Rounded</div>
    <div class="rule" style="background:${t.line}"></div>
    <div class="sec">Saved</div>
    <div class="small" style="display:flex;justify-content:space-between"><span>Saved conversations</span><span style="opacity:.7">3 ›</span></div>
  </div>`
}

// --- Saved conversations, borderless list on the same background -------------------------------------------
function savedList(t, { confirming = false } = {}) {
  const items = [['Today, 8:56 AM', 'Speaker 1: Happy birthday, Mom. Watch the screen…'], ['Today, 8:55 AM', 'Speaker 2: It\'s catching every word, even from…'], ['Yesterday, 7:12 PM', 'Speaker 1: So we finally tried the new place…']]
  return `<div class="topbar" style="color:${t.text}"><div style="position:absolute;left:0;font-size:17px;font-weight:700;color:${t.gear}">‹ Settings</div><span style="font-size:20px;font-weight:800">Saved</span></div>
  <div style="color:${t.text}">
    <div class="small" style="opacity:.7;margin:6px 0 10px">Kept for 30 days, then deleted.</div>
    <div style="border-bottom:1.5px solid ${t.line};padding:8px 0;font-size:16px;opacity:.6">Search</div>
    ${items.map(([d, s]) => `<div style="padding:14px 0;border-bottom:1px solid ${t.line}"><div style="font-weight:800;font-size:17px">${d}</div><div class="small" style="opacity:.75">${s}</div></div>`).join('')}
    <div style="margin-top:22px;text-align:center">${confirming
      ? `<div class="say" style="font-size:18px">Delete all 3 conversations?</div><div class="small" style="opacity:.75;margin:4px 0 12px">This can't be undone.</div><div style="display:flex;justify-content:center;gap:22px">${retro(t, 'Delete all', '#B3261E', 'font-size:22px')}${retro(t, 'Keep', null, 'font-size:22px')}</div>`
      : retro(t, 'Delete all', t.text, 'font-size:22px;opacity:.8')}</div>
  </div>`
}

// --- Main screen pieces -----------------------------------------------------------------------------------
const main = (t, status = 'Listening', { lines = LINES, captionsOpacity = 1 } = {}) => topbar(t, status) + captions(t, lines, captionsOpacity)
function paused(t, { save = 'Save', confirmNew = false } = {}) {
  const saveColor = save === 'Save' ? t.text : t.green
  const middle = confirmNew
    ? `<div style="text-align:center;color:${t.text};background:${t.bg};padding:16px 22px"><div class="say">Start a new conversation?</div><div class="small" style="opacity:.75;margin:6px 0 16px">This one isn't saved.</div><div style="display:flex;flex-direction:column;align-items:center;gap:18px">${retro(t, 'Start new')}${retro(t, 'Keep it')}</div></div>`
    : `<div style="display:flex;flex-direction:column;align-items:center;gap:22px">${retro(t, save, saveColor)}${retro(t, 'New')}</div>`
  return layer(main(t, 'Paused')) + veil(t) + `<div style="position:absolute;left:0;right:0;top:340px;z-index:20;display:grid;place-items:center">${middle}</div>` + startBtn(t)
}

// --- Static boards ------------------------------------------------------------------------------------------
const PAGES = []
const doc = (title, body, w, h) => `<!doctype html><html><head><meta charset="utf-8"><title>${title}</title><style>${CSS}</style></head><body style="width:${w}px;min-height:${h}px">${body}</body></html>`
const board = (title, sub, content) => `<div class="board"><h1>${title}</h1><div class="sub">${sub}</div>${content}</div>`
const fig = (p, cap, no = '') => `<div>${no ? `<div class="frame-no">${no}</div>` : ''}${p}<div class="cap">${cap}</div></div>`
const add = (file, title, html, w, h) => PAGES.push({ file, title, html: doc(title, html, w, h), w, h })

// (a) Settings as a fade on the same screen
const mainScr = (t) => phone(t, layer(main(t)) + stopDot())
const fadeFrame = (t, a, b) => phone(t, layer(main(t), `opacity:${a}`) + stopDot().replace('z-index:30', `z-index:30;opacity:${a}`) + layer(settingsScreen(t), `opacity:${b}`))
add('01-settings-fade.png', 'Settings fades in place',
  board('1 · Settings: fade out, fade in, same screen', 'Today Settings slides up as a sheet (a card over the screen, with Done). Proposed: tapping the gear fades the captions out and Settings in on the same background, about 0.25 s each way, with the gear staying exactly where it was. Tapping the gear again fades back. No card, no sheet edge, no Done. The same rule for every screen below.',
    `<div class="row">${fig(mainScr(T.paper), 'Tap the gear.', '1')}${fig(fadeFrame(T.paper, 0.25, 0), 'The captions fade out first (about 0.25 s)…', '2')}${fig(fadeFrame(T.paper, 0, 0.45), '…then Settings fades in (about 0.25 s).', '3')}${fig(phone(T.paper, layer(settingsScreen(T.paper))), 'Settings, on the same background. The gear (lightly highlighted) takes her back.', '4')}${fig(phone(T.paper, layer(settingsScreen(T.paper, { back: 'word' }))), 'Alternative: a "‹ Captions" word where the gear was.', 'alt')}</div>`), 2250, 1060)

// (b) Saved conversations the same way, (c) in-place delete confirmation
add('02-saved-fade.png', 'Saved conversations in place',
  board('2 · Saved conversations: same screen, no system list', 'Today: a system navigation bar, grey boxed rows, a system search field and an ellipsis menu, with a system pop-up for Delete all. Proposed: the list fades in over Settings on the same background, rows separated by one thin line, search as a plain underlined line, and the delete question asked in place in retro words.',
    `<div class="row">${fig(phone(T.paper, layer(savedList(T.paper))), 'The list. "‹ Settings" fades back.', '1')}${fig(phone(T.paper, layer(savedList(T.paper, { confirming: true }))), 'Delete all asks in place: no pop-up box.', '2')}${fig(phone(T.night, layer(savedList(T.night))), 'Dark (Night).', '3')}</div>`), 1400, 1060)

// (c) Every confirmation in place
const nameSpeaker = (t) => phone(t, layer(topbar(t, 'Listening') + `<div class="captions" style="color:${t.text}"><div><div class="spk" style="color:${t.s1}">Speaker 1</div>
  <div style="font-family:system-ui;font-size:17px;font-weight:700;border-bottom:2px solid ${t.s1};padding:4px 0;margin:2px 0 10px;color:${t.text}">Mo|<span style="opacity:.4"> name for this voice</span></div>
  <div style="display:flex;gap:18px;margin-bottom:8px">${retro(t, 'Save', null, 'font-size:20px')}${retro(t, 'Clear', null, 'font-size:20px;opacity:.75')}</div>So we finally tried the new place on Fifth, Luigi's.</div>
  <div><div class="spk" style="color:${t.s2}">Speaker 2</div>Oh, how was it? I heard the pasta is homemade.</div></div>`) + stopDot())
add('03-confirmations-in-place.png', 'Confirmations in place',
  board('3 · Every question asked in place, in retro words (no pop-up boxes)', 'Today these are system pop-ups: "Start a new conversation?" (an alert box), "Name this speaker" (an alert box with a text field) and "Delete all" (a system menu). Proposed: each one replaces the words where she tapped, in the retro style, and fades back when answered.',
    `<div class="row">${fig(phone(T.paper, paused(T.paper, { confirmNew: true })), '<b>[ New ]</b> with an unsaved conversation: the question takes the place of [ Save ] / [ New ]. [ Start new ] clears; [ Keep it ] fades back.', '1')}${fig(nameSpeaker(T.paper), '<b>Naming a speaker:</b> the field opens under the label itself, a plain underline; [ Save ] / [ Clear ].', '2')}${fig(phone(T.night, paused(T.night, { confirmNew: true })), 'Dark (Night).', '3')}</div>`), 1400, 1060)

// (d) Rating card and tour text: no boxes, fades
const ratingInPlace = (t, picked) => phone(t, layer(main(t, 'Paused')) + veil(t, 0.92) + `<div style="position:absolute;left:16px;right:16px;top:290px;z-index:20;color:${t.text};text-align:center;background:${t.bg};padding:16px 8px">
  <div class="say" style="font-size:23px">How well could you follow the conversation?</div>
  <div style="display:grid;grid-template-columns:repeat(10,1fr);gap:5px;margin-top:20px">${[...Array(10)].map((_, i) => `<div class="btn" style="height:44px;border-radius:14px;font-size:17px;${i + 1 === picked ? primary(t) : `background:${t.line};color:${t.text};box-shadow:0 3px 0 ${lip(t.line, 0.18)}`}">${i + 1}</div>`).join('')}</div>
  <div style="display:flex;justify-content:space-between;font-size:13px;font-weight:700;margin-top:8px;opacity:.75"><span>Not at all</span><span>Every word</span></div>
  <div style="display:flex;justify-content:space-between;margin-top:22px;font-size:17px;font-weight:700"><span style="color:${t.gear}">Add a note</span><span style="opacity:.7">Skip</span></div></div>` + startBtn(t))
add('04-cards-borderless.png', 'Rating and tour text without boxes',
  board('4 · The rating question and the tour words sit on the dim: no card, no border', 'Today the rating card and every tour step are white bordered cards that scale in. Proposed: the same words and buttons sit straight on the dim, which already separates them from the captions, and they only fade (no scaling).',
    `<div class="row">${fig(ratingInPlace(T.paper), '<b>Rating (beta only):</b> same question, same 1–10 gummy buttons, no card.', '1')}${fig(ratingInPlace(T.paper, 8), 'Tapped 8: it squishes, then everything fades.', '2')}${fig(ratingInPlace(T.night), 'Dark (Night).', '3')}</div>`), 1400, 1060)

// (e) Preparing without the seal box
const prepA = (t) => phone(t, layer(topbar(t, 'Getting ready…') + captions(t, LINES.slice(0, 2), 0.5)) + startBtn(t, 'Getting ready…', 'opacity:.85'))
const prepB = (t) => phone(t, layer(topbar(t, '') + `<div style="position:absolute;left:0;right:0;top:62px;height:64px;display:flex;justify-content:center;align-items:center;gap:8px;color:${t.text};font-size:15px;font-weight:600"><img src="${SEAL_TEAL}" style="width:34px;height:34px"><span style="opacity:.75">Getting ready…</span></div>` + captions(t, LINES.slice(0, 2), 0.5)) + startBtn(t, 'Getting ready…', 'opacity:.85'))
const prepNow = (t) => phone(t, `<div style="position:absolute;inset:0;background:${t.bg};display:grid;place-items:center;z-index:5"><div style="width:150px;height:150px;background:${TEAL};display:grid;place-items:center"><img src="../../../../../design/mascot/seal-rig.svg" style="width:150px"></div></div>`)
add('05-preparing.png', 'Getting ready after Start',
  board('5 · After tapping Start: no seal box', 'Today, if getting ready takes a moment, a full-screen cover with the seal in a square teal box appears (never approved). Proposed: nothing covers the screen. The Start pill already says "Getting ready…" while it morphs; option A puts the same words in the status row; option B adds the small seal face (no box) next to them.',
    `<div class="row">${fig(prepNow(T.paper), '<b>Today (not approved):</b> the seal in a square box covers the screen.', 'now')}${fig(prepA(T.paper), '<b>A:</b> words only, in the status row and on the pill.', 'A')}${fig(prepB(T.paper), '<b>B:</b> the same, with a small seal face (no box) beside the words.', 'B')}</div>`), 1400, 1060)

// (f) The voices explainer
const voicesNow = (t) => phone(t, layer(main(t)) + `<div style="position:absolute;left:30px;right:30px;top:130px;z-index:20;background:${t.text}1A;border-radius:12px;padding:14px;text-align:center;color:${t.text};font-size:15px">Seal tells voices apart as people talk.<div style="margin-top:8px;color:${t.gear}">Got it</div></div>` + stopDot())
const voicesLine = (t, o) => phone(t, layer(topbar(t, '') + `<div style="position:absolute;left:0;right:0;top:118px;text-align:center;color:${t.text};font-size:14px;opacity:${o}">Seal tells voices apart as people talk</div>` + `<div style="margin-top:22px">${captions(t)}</div>`).replace('Listening', '') + stopDot())
add('06-voices-explainer.png', 'The voices explainer',
  board('6 · "Seal tells voices apart as people talk."', 'Today: a box with "Got it" that stays until tapped and sits over the captions (never approved). Options: remove it entirely (the tour already covers speaker labels), or say it once as a borderless line under the status that fades out by itself after about 4 seconds and never covers a caption.',
    `<div class="row">${fig(voicesNow(T.paper), '<b>Today (not approved):</b> a boxed banner over the captions until "Got it".', 'now')}${fig(voicesLine(T.paper, 1), '<b>Option:</b> one plain line under the status, the first time a second voice appears…', '1')}${fig(voicesLine(T.paper, 0.25), '…fading out by itself after about 4 s. Never shown again.', '2')}</div>`), 1400, 1060)

// (g) Tour v2: action-required
const tourFrame = (t, { status = 'Ready', words, sub, lit = '', body = '', hole = null, start = true, startLabel = 'Start captions', stop = false, save = null, step }) => {
  const dimCut = hole ? `<div style="position:absolute;z-index:15;left:${hole[0]}px;top:${hole[1]}px;width:${hole[2]}px;height:${hole[3]}px;border-radius:${hole[4] ?? 32}px;box-shadow:0 0 0 2000px ${t.bg}E6"></div>` : `<div style="position:absolute;inset:0;background:${t.bg};opacity:.9;z-index:15"></div>`
  return phone(t, layer(topbar(t, status) + body) + dimCut +
    `<div style="position:absolute;left:28px;right:28px;top:${words.top ?? 520}px;z-index:25;color:${t.text};text-align:center"><div class="say">${words.text}</div><div class="small" style="opacity:.8;margin-top:6px">${sub}</div></div>` +
    `<div style="position:absolute;right:22px;top:72px;z-index:25;color:${t.text};font-size:15px;font-weight:700;opacity:.8">Skip tour</div>` +
    `<div style="position:absolute;left:22px;top:${words.top ? words.top - 36 : 484}px;z-index:25;color:${t.text};font-size:14px;font-weight:700;opacity:.55">${step} of 7${step > 1 ? ' · ‹ Back' : ''}</div>` +
    (save ? `<div style="position:absolute;left:0;right:0;top:330px;z-index:20;display:flex;flex-direction:column;align-items:center;gap:22px">${save}</div>` : '') +
    (start ? startBtn(t, startLabel) : '') + (stop ? stopDot() : ''))
}
const p = T.paper
const myWords = `<div class="captions" style="color:${p.text}"><div><div class="spk" style="color:${p.s1}">Speaker 1</div>Hi, is this working? I can see my words!</div></div>`
const frames = [
  tourFrame(p, { step: 1, words: { text: 'Tap Start captions', top: 560 }, sub: 'Put the phone on the table between you. The tour waits for you.', hole: [16, 790, 370, 72, 36] }),
  tourFrame(p, { step: 2, status: 'Listening', words: { text: 'Say hello', top: 330 }, sub: 'Talk, or ask someone to. When your own words appear, the tour moves on. (Too quiet? "Show me an example" after 6 s.)', start: false, stop: true, body: '', hole: [16, 130, 370, 120, 20] }),
  tourFrame(p, { step: 2, status: 'Listening', words: { text: 'Those are your words.', top: 330 }, sub: 'Every new voice gets its own label.', start: false, stop: true, body: myWords, hole: [16, 130, 370, 150, 20] }),
  tourFrame(p, { step: 3, status: 'Listening', words: { text: 'Tap ✕ to pause', top: 560 }, sub: 'Nothing is lost. Start captions carries on where you left off.', start: false, stop: true, body: myWords, hole: [312, 784, 76, 76, 38] }),
  tourFrame(p, { step: 4, status: 'Paused', words: { text: 'Tap [ Save ]', top: 560 }, sub: 'Keeps it for 30 days. Watch it turn green.', body: myWords, save: retro(p, 'Save') + retro(p, 'New'), hole: [110, 318, 182, 56, 12] }),
  tourFrame(p, { step: 4, status: 'Paused', words: { text: 'Saved.', top: 560 }, sub: '[ Saved ] stays green until something new is said.', body: myWords, save: retro(p, 'Saved', p.green) + retro(p, 'New'), hole: [110, 318, 182, 56, 12] }),
  tourFrame(p, { step: 5, status: 'Paused', words: { text: 'Hold on your words', top: 560 }, sub: 'Press and hold, stretch the selection, then tap Copy.', body: myWords.replace('I can see my words!', '<span style="background:#1F998B44;border-radius:4px">I can see my words!</span>'), hole: [16, 130, 370, 150, 20] }),
  tourFrame(p, { step: 6, status: 'Paused', words: { text: 'Tap the gear', top: 560 }, sub: 'Colors, size and lettering. Tap the gear again to come back.', body: myWords, hole: [16, 66, 52, 52, 26] }),
  tourFrame(p, { step: 7, status: 'Paused', words: { text: "You're all set.", top: 470 }, sub: '[ New ] clears the screen for a fresh conversation. It asks first, so a stray tap won\'t wipe it. You can take this tour again from Settings.', body: myWords, save: retro(p, 'Saved', p.green) + retro(p, 'New'), hole: [130, 395, 142, 56, 12] }),
]
add('07-tour-v2.png', 'Tour v2: she does each thing',
  board('7 · Tour v2: each step waits for her to really do it', 'Proposed: no Next button on any step that asks for an action, the step moves on only when she actually does it (real Start, her own words, ✕, [ Save ], hold to copy, the gear). Back and Skip tour stay on every step. The words sit on the dim (no card); the lit control has a soft edge, no white frame. [ Save ] gets its full [ ✔ ] → [ Saved ] moment before the next step fades in (today the next card covers it).',
    `<div class="row">${frames.map((f, i) => fig(f, ['Only Start is lit; nothing else answers.', 'Waiting for her voice. The example is only offered after 6 s of quiet.', 'Her own words: the step moves on by itself after a beat.', 'Only ✕ is lit.', 'Only [ Save ] is lit.', '[ Saved ] gets its moment; then the next step fades in.', 'Hold on her own words; Copy appears; the step moves on after she copies.', 'Settings fades in; the step finishes when she comes back.', 'Done. [ New ] is explained, not forced (it would clear her practice).'][i], String(i + 1))).join('')}</div>`), 1950, 2040)

// --- Animated GIFs (frame-by-frame, deterministic) -----------------------------------------------------------
const ANIMS = []
const animDoc = (body, script) => `<!doctype html><html><head><meta charset="utf-8"><style>${CSS} body{background:#E9E4DA;padding:20px;width:462px;height:934px}</style></head><body>${body}<script>${script}</script></body></html>`
const ease = `const ease=(x)=>x<0?0:x>1?1:x<.5?4*x*x*x:1-Math.pow(-2*x+2,3)/2; const seg=(t,a,b)=>ease((t-a)/(b-a));`

// Settings fade: main → settings → main
ANIMS.push({ file: 'anim-settings-fade.gif', duration: 3.2, html: animDoc(
  phone(p, `<div id="m">${layer(main(p))}${stopDot()}</div><div id="s" style="opacity:0">${layer(settingsScreen(p))}</div>`),
  `${ease} window.render=(t)=>{const out=seg(t,.6,.85)-seg(t,2.2,2.45); const inn=seg(t,.85,1.1)-seg(t,1.95,2.2);
   document.getElementById('m').style.opacity=1-Math.max(0,out); document.getElementById('s').style.opacity=Math.max(0,inn);}`) })

// Save → ✔ → Saved, then New asks in place
ANIMS.push({ file: 'anim-save-new-inplace.gif', duration: 5.2, html: animDoc(
  phone(p, layer(main(p, 'Paused')) + veil(p) + `<div style="position:absolute;left:0;right:0;top:340px;z-index:20;display:grid;place-items:center">
    <div id="pair" style="display:flex;flex-direction:column;align-items:center;gap:22px;position:relative">
      <div style="position:relative;height:36px;width:200px;display:grid;place-items:center"><div id="w1" style="position:absolute">${retro(p, 'Save')}</div><div id="w2" style="position:absolute;opacity:0">${retro(p, '✔', p.green)}</div><div id="w3" style="position:absolute;opacity:0">${retro(p, 'Saved', p.green)}</div></div>
      ${retro(p, 'New')}</div>
    <div id="q" style="position:absolute;opacity:0;text-align:center;color:${p.text}"><div class="say">Start a new conversation?</div><div class="small" style="opacity:.75;margin:6px 0 16px">This one is saved, so nothing is lost.</div><div style="display:flex;flex-direction:column;align-items:center;gap:18px">${retro(p, 'Start new')}${retro(p, 'Keep it')}</div></div></div>` + startBtn(p)),
  `${ease} window.render=(t)=>{const o=(id,v)=>document.getElementById(id).style.opacity=v;
   o('w1',1-seg(t,.5,.7)); o('w2',seg(t,.5,.7)-seg(t,1.3,1.5)); o('w3',seg(t,1.3,1.5));
   o('pair',1-seg(t,3,3.3)); o('q',seg(t,3.3,3.6));}`) })

// Launch hand-off, smoother: continuous iris (no hard cut), arcing jump with squash and stretch, splash, ripples
ANIMS.push({ file: 'anim-launch-handoff-smooth.gif', duration: 3.4, fps: 30, html: animDoc(
  phone(p, `<div style="position:absolute;inset:0">${layer(main(p, 'Ready', { lines: [] }))}${startBtn(p)}</div>
    <div id="green" style="position:absolute;inset:0;background:${TEAL};z-index:40"></div>
    <div id="pool" style="position:absolute;z-index:41;left:201px;top:520px;width:0;height:0;border-radius:50%;background:${TEAL};transform:translate(-50%,-50%)"></div>
    <img id="seal" src="${SEAL}" style="position:absolute;z-index:45;left:201px;top:400px;width:230px;transform:translate(-50%,-50%)">
    <div id="rings" style="position:absolute;inset:0;z-index:44;pointer-events:none"></div>`),
  `${ease}
  const rings=document.getElementById('rings'); for(let i=0;i<3;i++){const r=document.createElement('div');r.style.cssText='position:absolute;left:201px;top:520px;border:3px solid ${TEAL};border-radius:50%;transform:translate(-50%,-50%);opacity:0';rings.appendChild(r)}
  const drops=[]; for(let i=0;i<9;i++){const d=document.createElement('div');d.style.cssText='position:absolute;width:10px;height:10px;border-radius:50%;background:${TEAL};opacity:0;left:201px;top:520px';rings.appendChild(d);drops.push(d)}
  window.render=(t)=>{
    const g=document.getElementById('green'), pool=document.getElementById('pool'), seal=document.getElementById('seal');
    // 0–1.0 s: the green irises continuously from full screen down to a 120 px pool behind the seal (no cut).
    const ir=seg(t,0,1.0); const R=580*(1-ir)+60*ir;   // starts just past the farthest corner, so the shrink is visible from frame one
    g.style.clipPath='circle('+R+'px at 201px 520px)';
    // 0.9–1.5 s: crouch then an arcing jump with stretch, landing into the pool with squash.
    const crouch=seg(t,.85,1.0)-seg(t,1.0,1.1); const jump=seg(t,1.05,1.55);
    const x=201, y=400+120*jump-110*Math.sin(Math.PI*jump), s=1-0.55*jump;
    const sy=1-0.12*crouch+0.15*Math.sin(Math.PI*jump), sx=1+0.10*crouch-0.08*Math.sin(Math.PI*jump);
    seal.style.transform='translate(-50%,-50%) scale('+(s*sx)+','+(s*sy)+')'; seal.style.top=y+'px'; seal.style.left=x+'px';
    seal.style.opacity=1-seg(t,1.5,1.62);
    // 1.5–1.9 s: splash droplets arc out and fall; the pool closes.
    const sp=seg(t,1.5,2.0); drops.forEach((d,i)=>{const a=-Math.PI*(0.15+0.7*i/8); const r=70*sp; d.style.left=(201+Math.cos(a)*r-5)+'px'; d.style.top=(520+Math.sin(a)*r+60*sp*sp-5)+'px'; d.style.opacity=t<1.5?0:1-seg(t,1.85,2.1)});
    g.style.opacity=1-seg(t,1.55,1.9);
    // 1.6–3.2 s: three rings ripple out and fade over the main screen.
    [...rings.children].slice(0,3).forEach((r,i)=>{const k=seg(t,1.6+0.18*i,3.0+0.18*i); const D=40+520*k; r.style.width=D+'px'; r.style.height=D+'px'; r.style.opacity=t<1.6+0.18*i?0:0.8*(1-k)});
  }`) })

// Tour: [ Save ] gets its moment, then the next words fade in (no box)
ANIMS.push({ file: 'anim-tour-save-moment.gif', duration: 4.6, html: animDoc(
  phone(p, layer(topbar(p, 'Paused') + myWords) + `<div style="position:absolute;z-index:15;left:110px;top:318px;width:182px;height:56px;border-radius:12px;box-shadow:0 0 0 2000px ${p.bg}E6"></div>
    <div style="position:absolute;left:0;right:0;top:330px;z-index:20;display:flex;flex-direction:column;align-items:center;gap:22px"><div style="position:relative;height:36px;width:200px;display:grid;place-items:center"><div id="w1" style="position:absolute">${retro(p, 'Save')}</div><div id="w2" style="position:absolute;opacity:0">${retro(p, '✔', p.green)}</div><div id="w3" style="position:absolute;opacity:0">${retro(p, 'Saved', p.green)}</div></div>${retro(p, 'New')}</div>
    <div id="a" style="position:absolute;left:28px;right:28px;top:560px;z-index:25;color:${p.text};text-align:center"><div class="say">Tap [ Save ]</div><div class="small" style="opacity:.8;margin-top:6px">Keeps it for 30 days. Watch it turn green.</div></div>
    <div id="b" style="position:absolute;left:28px;right:28px;top:560px;z-index:25;color:${p.text};text-align:center;opacity:0"><div class="say">Saved.</div><div class="small" style="opacity:.8;margin-top:6px">Next: hold on your words to copy them.</div></div>` + startBtn(p)),
  `${ease} window.render=(t)=>{const o=(id,v)=>document.getElementById(id).style.opacity=v;
   o('w1',1-seg(t,.8,1.0)); o('w2',seg(t,.8,1.0)-seg(t,1.6,1.8)); o('w3',seg(t,1.6,1.8));
   o('a',1-seg(t,2.2,2.5)); o('b',seg(t,2.5,2.8));}`) })

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
const tmp = fs.mkdtempSync('/private/tmp/claude-501/round2-frames-')
const anim = await browser.newPage({ deviceScaleFactor: 1, viewport: { width: 462, height: 934 } })
for (const a of ANIMS) {
  const htmlPath = path.join(SRC, a.file.replace('.gif', '.html'))
  fs.writeFileSync(htmlPath, a.html)
  await anim.goto('file://' + htmlPath)
  await anim.evaluate(() => document.fonts.ready)
  await anim.waitForTimeout(250)
  const fps = a.fps ?? 20
  const dir = fs.mkdtempSync(path.join(tmp, 'f-'))
  const n = Math.round(a.duration * fps)
  for (let i = 0; i <= n; i++) {
    await anim.evaluate((t) => window.render(t), i / fps)
    await anim.screenshot({ path: path.join(dir, String(i).padStart(4, '0') + '.png') })
  }
  execFileSync('ffmpeg', ['-y', '-loglevel', 'error', '-framerate', String(fps), '-i', path.join(dir, '%04d.png'), '-vf',
    'scale=420:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=128[p];[b][p]paletteuse=dither=bayer', path.join(OUT, a.file)])
  console.log('animated', a.file, n + 1, 'frames')
}
await browser.close()
