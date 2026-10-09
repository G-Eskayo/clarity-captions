// Generates the v1 polish mock-ups (docs/design/v1-polish-spec.md) as HTML and renders them to PNG at 3x.
// Run: NODE_PATH=~/.agents/dashboard/node_modules node build.mjs
// Mock-ups only: nothing here ships in the app.
import fs from 'node:fs'
import path from 'node:path'
import { createRequire } from 'node:module'

const require = createRequire(path.join(process.env.HOME, '.agents/dashboard/node_modules/'))
const { chromium } = require('playwright-core')

const SRC = import.meta.dirname
const OUT = path.resolve(SRC, '..')

// ---------- palette (from design/icon and LaunchBackground) ----------
const BRAND = { teal: '#1F998B', deep: '#0F5C55', cream: '#FBE8C6', peach: '#EDC688', launchDark: '#0F3F3C' }
const GREEN = { fill: '#1E7A4C', light: '#DDF3E6' }

// ---------- WCAG contrast ----------
function lum(hex) {
  const c = hex.replace('#', '').match(/../g).map((h) => parseInt(h, 16) / 255)
  const [r, g, b] = c.map((v) => (v <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4))
  return 0.2126 * r + 0.7152 * g + 0.0722 * b
}
export function contrast(a, b) {
  const [x, y] = [lum(a), lum(b)].sort((p, q) => q - p)
  return (x + 0.05) / (y + 0.05)
}

// ---------- themes: 3 light, 3 dark ----------
// Light: Paper (existing) plus Sea Glass and Peach in the icon's palette. Dark (revised 2026-10-09 after the owner's
// feedback): Bright (yellow on black) is dropped, and every dark theme is relaxed for older eyes: no pure black
// behind, no pure white text; soft deep grey, navy and teal with warm off-white text, still >= 7:1.
const THEMES = [
  { id: 'paper', name: 'Paper', kind: 'light', bg: '#FAF5E6', text: '#141419', gear: '#14514B', s1: '#14514B', s2: '#7A350C', green: '#12512F', status: 'existing' },
  { id: 'seaglass', name: 'Sea Glass', kind: 'light', bg: '#DCEFEA', text: '#0D2F2C', gear: '#0B4842', s1: '#0B4842', s2: '#6E2E0A', green: '#12512F', status: 'new' },
  { id: 'peach', name: 'Peach', kind: 'light', bg: '#FBE8D2', text: '#2B1A10', gear: '#6E2E0A', s1: '#0B4842', s2: '#6E2E0A', green: '#12512F', status: 'new' },
  { id: 'charcoal', name: 'Charcoal', kind: 'dark', bg: '#2B2D31', text: '#ECE6D9', gear: '#E2D9C6', s1: '#93DCD1', s2: '#F2C994', green: '#9BE3B4', status: 'replaces Classic' },
  { id: 'night', name: 'Night', kind: 'dark', bg: '#1D2536', text: '#E9E3D5', gear: '#C9D6F2', s1: '#93DCD1', s2: '#F2C994', green: '#9BE3B4', status: 'softened' },
  { id: 'harbor', name: 'Harbor', kind: 'dark', bg: '#173331', text: '#ECE4D3', gear: '#F2DDB5', s1: '#A3E3D9', s2: '#F2C994', green: '#A6E8BC', status: 'new' },
]
const T = Object.fromEntries(THEMES.map((t) => [t.id, t]))

// ---------- shared CSS ----------
const CSS = `
@font-face { font-family: 'OpenDyslexic'; src: url('fonts/OpenDyslexic-Regular.woff') format('woff'); font-weight: 400; }
@font-face { font-family: 'OpenDyslexic'; src: url('fonts/OpenDyslexic-Bold.woff') format('woff'); font-weight: 700; }
* { box-sizing: border-box; margin: 0; padding: 0; }
body { font-family: -apple-system, BlinkMacSystemFont, 'SF Pro Rounded', 'Helvetica Neue', sans-serif; background: #E9E4DA; color: #1b1b1b; }
.board { padding: 36px; display: flex; flex-direction: column; gap: 22px; }
.board h1 { font-size: 26px; font-weight: 800; color: #0F3F3C; }
.board .sub { font-size: 15px; color: #3d4b4a; max-width: 1100px; line-height: 1.45; }
.row { display: flex; gap: 32px; align-items: flex-start; flex-wrap: wrap; }
.cap { font-size: 14px; color: #2a3534; margin-top: 10px; max-width: 402px; line-height: 1.4; }
.cap b { color: #0F3F3C; }
.phone { position: relative; border-radius: 54px; overflow: hidden; box-shadow: 0 0 0 10px #1b1d1f, 0 18px 40px rgba(0,0,0,.25); flex: none; }
.phone.p { width: 402px; height: 874px; }
.phone.l { width: 874px; height: 402px; }
.island { position: absolute; background: #000; border-radius: 20px; z-index: 50; }
.p .island { top: 11px; left: 50%; width: 124px; height: 36px; transform: translateX(-50%); }
.l .island { left: 11px; top: 50%; width: 36px; height: 124px; transform: translateY(-50%); }
.statusbar { position: absolute; top: 18px; left: 34px; right: 30px; display: flex; justify-content: space-between; font-weight: 600; font-size: 16px; z-index: 40; }
.l .statusbar { display: none; }
.screen { position: absolute; inset: 0; }
.p .screen { padding: 62px 20px 34px; }
.l .screen { padding: 18px 64px 20px 64px; }
.topbar { position: relative; height: 64px; display: flex; align-items: center; justify-content: center; z-index: 20; }
.gear { position: absolute; left: 0; top: 50%; transform: translateY(-50%); width: 44px; height: 44px; display: grid; place-items: center; }
.status { position: relative; z-index: 20; text-align: center; font-size: 15px; font-weight: 600; opacity: .75; margin-top: 2px; display: flex; gap: 6px; justify-content: center; align-items: center; }
.dot { width: 9px; height: 9px; border-radius: 50%; }
.captions { font-family: 'OpenDyslexic', sans-serif; font-size: 22px; line-height: 1.5; margin-top: 18px; display: flex; flex-direction: column; gap: 16px; }
.l .captions { font-size: 20px; gap: 10px; margin-top: 8px; }
.spk { font-family: system-ui, BlinkMacSystemFont, sans-serif; font-size: 14px; font-weight: 800; letter-spacing: .02em; text-transform: none; margin-bottom: 1px; }
.vol { opacity: .55; }
.sound { font-style: italic; opacity: .8; }
/* buttons: option A (gummy pill with a flat lip) is the default look in the screens */
.btn { border: none; font-family: -apple-system, 'SF Pro Rounded', sans-serif; font-weight: 800; letter-spacing: .04em; display: inline-flex; align-items: center; justify-content: center; gap: 10px; cursor: default; }
.start { height: 60px; padding: 0 34px; border-radius: 30px; font-size: 21px; }
.stopdot { width: 56px; height: 56px; border-radius: 50%; display: grid; place-items: center; }
.small { height: 52px; width: 190px; border-radius: 26px; font-size: 19px; }
.dim { position: absolute; inset: 0; z-index: 10; }
.overlay-buttons { position: absolute; left: 0; right: 0; display: flex; flex-direction: column; align-items: center; gap: 14px; z-index: 30; }
.chip { position: absolute; left: 50%; transform: translateX(-50%); padding: 10px 16px; border-radius: 22px; font-size: 14px; font-weight: 700; z-index: 30; white-space: nowrap; }
.touch { position: absolute; width: 70px; height: 70px; border-radius: 50%; z-index: 35; }
.sel { border-radius: 4px; }
.handle { position: absolute; width: 3px; z-index: 5; }
.handle::after { content: ''; position: absolute; left: -5px; width: 13px; height: 13px; border-radius: 50%; background: inherit; }
.handle.s::after { top: -11px; }
.handle.e::after { bottom: -11px; }
.anno { position: absolute; z-index: 60; font-size: 13px; font-weight: 700; background: #FFF6D8; color: #5b3a00; border: 2px solid #E0A400; border-radius: 10px; padding: 6px 10px; max-width: 200px; line-height: 1.3; }
`

const GEAR = (color, size = 30) => `<svg width="${size}" height="${size}" viewBox="0 0 24 24" fill="none" stroke="${color}" stroke-width="2.1" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="3.2"/><path d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 1 1-2.83 2.83l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 1 1-4 0v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 1 1-2.83-2.83l.06-.06A1.65 1.65 0 0 0 4.68 15a1.65 1.65 0 0 0-1.51-1H3a2 2 0 1 1 0-4h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 1 1 2.83-2.83l.06.06A1.65 1.65 0 0 0 9 4.68a1.65 1.65 0 0 0 1-1.51V3a2 2 0 1 1 4 0v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 1 1 2.83 2.83l-.06.06A1.65 1.65 0 0 0 19.4 9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 1 1 0 4h-.09a1.65 1.65 0 0 0-1.51 1z"/></svg>`
const XICON = (c) => `<svg width="24" height="24" viewBox="0 0 24 24" stroke="${c}" stroke-width="3.2" stroke-linecap="round"><path d="M6 6l12 12M18 6L6 18"/></svg>`
const CHECK = (c, s = 30) => `<svg width="${s}" height="${s}" viewBox="0 0 24 24" fill="none" stroke="${c}" stroke-width="3.4" stroke-linecap="round" stroke-linejoin="round"><path d="M5 12.5l4.5 4.5L19 7.5"/></svg>`

// Gummy pill with a flat darker lip (option A). Colors derive from the theme.
function lipColor(hex, amt = 0.28) {
  const c = hex.replace('#', '').match(/../g).map((h) => parseInt(h, 16))
  const dark = lum(hex) < 0.25
  const out = c.map((v) => Math.round(dark ? v + (255 - v) * amt : v * (1 - amt)))
  return '#' + out.map((v) => v.toString(16).padStart(2, '0')).join('')
}
function primaryStyle(t) {
  // Start uses the theme's text color as fill (as today's MorphingControl does), background color as label.
  return `background:${t.text};color:${t.bg};box-shadow:0 6px 0 ${lipColor(t.text)};`
}
function secondaryStyle(t) {
  const fill = t.kind === 'light' ? '#FFFFFF' : '#2A2F33'
  const fg = t.kind === 'light' ? t.text : '#FFFFFF'
  return `background:${fill};color:${fg};box-shadow:0 5px 0 ${t.kind === 'light' ? '#CFC6B5' : '#14181B'};`
}

const LINES = [
  { s: 1, t: "So we finally tried the new place on Fifth, Luigi's." },
  { s: 2, t: 'Oh, how was it? I heard the pasta is homemade.' },
  { s: 1, t: 'So good. The waiter said they make the ravioli every morning.' },
  { sound: '[Laughter]' },
  { s: 2, t: "We should take your mom there for her birthday." },
  { s: 1, t: "Yes! Let's book a table for Saturday around seven." },
  { s: 2, t: 'I can call them tomorrow and', vol: true },
]

function captionsHTML(t, { lines = LINES, selection = null, compact = false } = {}) {
  return `<div class="captions" style="color:${t.text}">` + lines.map((l, i) => {
    if (l.sound) return `<div class="sound">${selection && selection[i] ? selection[i] : l.sound}</div>`
    let text = l.t
    if (selection && selection[i]) text = selection[i]
    return `<div class="${l.vol ? 'vol' : ''}"><div class="spk" style="color:${l.s === 1 ? t.s1 : t.s2}">Speaker ${l.s}</div>${text}</div>`
  }).join('') + `</div>`
}

function phone(orient, t, inner, extraStyle = '') {
  const bar = `<div class="statusbar" style="color:${t.text}"><span>9:41</span><span>●●●● ▮</span></div>`
  return `<div class="phone ${orient}" style="background:${t.bg};${extraStyle}"><div class="island"></div>${bar}<div class="screen">${inner}</div></div>`
}

function topbar(t, center = '') {
  return `<div class="topbar"><div class="gear">${GEAR(t.gear)}</div>${center}</div>`
}
const listeningStatus = (t) => `<div class="status" style="color:${t.text}"><span class="dot" style="background:${t.text}"></span>Listening</div>`
const pausedStatus = (t) => `<div class="status" style="color:${t.text}">Paused</div>`
// Bottom controls, as in today's app: Start is the wide pill at the bottom middle; while captioning it shrinks into
// the small Stop circle at the bottom right (MorphingControl).
const stopDot = (t) => `<div class="stopdot btn" style="position:absolute;right:20px;bottom:34px;z-index:30;${primaryStyle(t)}">${XICON(t.bg)}</div>`
const startBtn = (t, orient = 'p', extra = '') => `<div class="btn start" style="position:absolute;left:50%;transform:translateX(-50%);bottom:${orient === 'p' ? 40 : 26}px;width:${orient === 'p' ? 362 : 420}px;z-index:30;${primaryStyle(t)}${extra}">Start captions</div>`

// The pause veil fades the captions back toward the theme's own background, so the buttons keep full theme contrast.
function dimLayer(t, opacity = 1) {
  return `<div class="dim" style="background:${t.bg};opacity:${0.86 * opacity}"></div>`
}
// Retro, literal text buttons: [ Save ] -> [ ✔ ] -> [ Saved ] (green, held until the conversation changes); [ New ].
const RETRO = "font-family:'SF Mono',Menlo,ui-monospace,monospace;font-weight:700;font-size:26px;letter-spacing:.02em;white-space:pre"
function retro(t, label, color) { return `<div style="${RETRO};color:${color || t.text};background:${t.bg};padding:4px 16px;border-radius:14px">[ ${label} ]</div>` }
function saveNew(t, saveState = 'save', top = 300) {
  const save = saveState === 'save' ? retro(t, 'Save') : saveState === 'check' ? retro(t, '✔', t.green) : retro(t, 'Saved', t.green)
  return `<div class="overlay-buttons" style="top:${top}px;gap:26px">${save}${retro(t, 'New')}</div>`
}

function doc(title, body, width, height) {
  return `<!doctype html><html><head><meta charset="utf-8"><title>${title}</title><style>${CSS}</style></head><body style="width:${width}px;min-height:${height}px">${body}</body></html>`
}
function board(title, sub, content) {
  return `<div class="board"><h1>${title}</h1><div class="sub">${sub}</div>${content}</div>`
}
const fig = (phoneHTML, caption) => `<div>${phoneHTML}<div class="cap">${caption}</div></div>`

// ---------- screens ----------
const theme = T.paper

function mainCaptioning(orient, t = theme) {
  return phone(orient, t, topbar(t) + listeningStatus(t) + captionsHTML(t, { lines: orient === 'l' ? LINES.slice(2) : LINES }) + stopDot(t))
}
function paused(orient, t = theme, { saveState = 'save', dimOpacity = 1, hideButtons = false } = {}) {
  const top = orient === 'p' ? 330 : 120
  const inner = topbar(t) + pausedStatus(t) + captionsHTML(t, { lines: orient === 'l' ? LINES.slice(2, 6) : LINES.slice(0, 6) })
    + dimLayer(t, dimOpacity) + (hideButtons ? '' : saveNew(t, saveState, top)) + startBtn(t, orient)
  return phone(orient, t, inner.replace('<div class="topbar">', '<div class="topbar" style="z-index:20">'))
}

const PAGES = []
const add = (file, title, html, w, h) => PAGES.push({ file, title, html: doc(title, html, w, h), w, h })

// 01 main screen while captioning
add('01-main-captioning.png', 'Main screen while captioning',
  board('1 · Main screen while captioning', 'Gear in the top-left corner: icon only, no label, no background, colored for the theme. Stop is today\'s small circle with an X at the bottom right: the wide Start pill at the bottom middle shrinks into it when captioning starts (today\'s behavior, unchanged). Captions in the dyslexia-friendly font, the new default. Theme shown: Paper.',
    `<div class="row">${fig(mainCaptioning('p'), '<b>Portrait.</b> Gear top-left, "Listening" at the top, small Stop circle bottom right.')}${fig(mainCaptioning('l'), '<b>Landscape.</b> Same; captions use the full width.')}</div>`), 1400, 1000)

// 02 paused
add('02-paused-save-new.png', 'Paused: Start, Save, New',
  board('2 · Paused (after pressing X)', 'The X grows back into Start captions at the bottom middle, exactly as it works today. The captions fade back and the retro text buttons [ Save ] and [ New ] fade in, centered. Pressing Start captions fades the veil and both buttons back to clear and the same conversation carries on.',
    `<div class="row">${fig(paused('p'), '<b>Portrait.</b> [ Save ] over [ New ], centered; Start at the bottom middle.')}${fig(paused('l'), '<b>Landscape.</b> Same, centered in the wider screen.')}</div><div class="row">${fig(paused('p', T.night), '<b>Dark (Night).</b> Same layout; the veil fades toward the theme\'s own background, so the text keeps full contrast.')}</div>`), 1400, 1950)

// 03 save animation strip
add('03-save-animation.png', 'Save animation',
  board('3 · Save: [ Save ] → [ ✔ ] → [ Saved ]', 'Tap [ Save ]: it becomes [ ✔ ] in green, then [ Saved ] in green, and holds solid. It only turns back into [ Save ] when the conversation\'s content changes (new captions after Start captions), never because time passed. Saving again updates the same saved conversation.',
    `<div class="row">${fig(paused('p', theme, { saveState: 'save' }), '<b>1.</b> [ Save ] when paused.')}${fig(paused('p', theme, { saveState: 'check' }), '<b>2.</b> Tap: [ ✔ ] in green.')}${fig(paused('p', theme, { saveState: 'saved' }), '<b>3.</b> [ Saved ] in green, held until something changes.')}</div>
    <div class="row">${fig(paused('p', T.night, { saveState: 'saved' }), '<b>Dark.</b> The green is lightened for dark themes so it stays easy to read.')}</div>`), 1400, 1950)

// 04 veil cleared + hold on empty space
function clearedFrame(withTouch) {
  const t = theme
  const hint = `<div class="chip" style="bottom:120px;background:${t.text};color:${t.bg}">Hold on empty space to bring back Save and New</div>`
  let inner = topbar(t) + pausedStatus(t) + captionsHTML(t, { lines: LINES.slice(0, 6) })
  if (!withTouch) inner += hint
  else inner += dimLayer(t, 0.5) + saveNew(t, 'save', 330).replace('style="top:330px', 'style="opacity:.5;top:330px')
    + `<div class="touch" style="left:300px;bottom:106px;background:rgba(31,153,139,.35);box-shadow:0 0 0 10px rgba(31,153,139,.18),0 0 0 22px rgba(31,153,139,.08)"></div>`
    + `<div class="anno" style="left:24px;top:96px;max-width:300px">Press and hold on empty space: the veil and buttons fade back in</div>`
  return phone('p', t, inner + startBtn(t))
}
add('04-dim-cleared-and-back.png', 'Veil cleared for scrolling and copying',
  board('4 · Clearing the veil to scroll and copy', 'While paused, one tap on the faded area clears the veil and [ Save ] / [ New ], so she can scroll and select text. Start stays put. Press and hold on empty space (not on words) brings them back; press and hold on words selects text (see 5). For your sign-off (Decisions).',
    `<div class="row">${fig(paused('p'), '<b>1.</b> Paused.')}${fig(clearedFrame(false), '<b>2.</b> One tap: clear. A small hint shows the first few times.')}${fig(clearedFrame(true), '<b>3.</b> Press and hold on empty space: veil and buttons fade back in.')}</div>`), 1400, 1000)

// 05 copy
function copyFrame() {
  const t = theme
  const hl = (s) => `<span class="sel" style="background:rgba(31,153,139,.30)">${s}</span>`
  const sel = {
    2: `So good. The waiter said <span id="selS"></span>${hl('they make the ravioli every morning.')}`,
    3: `${hl('[Laughter]')}`,
    4: `${hl("We should take your mom there for her birthday.")}`,
    5: `${hl("Yes! Let's book a table for Saturday")}<span id="selE"></span> around seven.`,
  }
  const inner = topbar(t) + pausedStatus(t) + captionsHTML(t, { lines: LINES.slice(0, 6), selection: sel })
    + `<div id="hS" class="handle s" style="background:#1F998B;height:32px"></div><div id="hE" class="handle e" style="background:#1F998B;height:32px"></div>`
    + `<script>addEventListener('load',()=>document.fonts.ready.then(()=>{const scr=document.querySelector('#hS').parentElement.getBoundingClientRect();for(const[m,h]of[['selS','hS'],['selE','hE']]){const r=document.getElementById(m).getBoundingClientRect();const el=document.getElementById(h);el.style.left=(r.left-scr.left-1)+'px';el.style.top=(r.top-scr.top+2)+'px'}}))</script>`
    + `<div class="btn" style="position:absolute;left:50%;transform:translateX(-50%);top:330px;z-index:30;height:50px;padding:0 26px;border-radius:25px;font-size:19px;background:${t.text};color:${t.bg};box-shadow:0 5px 0 ${lipColor(t.text)}"><svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="${t.bg}" stroke-width="2.4"><rect x="9" y="9" width="11" height="11" rx="2.5"/><path d="M5 15V6a2 2 0 0 1 2-2h9"/></svg>Copy</div>`
    + startBtn(t)
  return phone('p', t, inner)
}
add('05-copy.png', 'Copy: only a Copy button',
  board('5 · Copying text', 'Press and hold on words to select, drag the handles across lines. About half a second after the selection stops changing, only a Copy button appears (no Look Up, Share or other menu items). The handles still work after Copy appears. This replaces the Copy all / Share options that were in Settings.',
    `<div class="row">${fig(copyFrame(), '<b>Selection across several lines</b>, handles at both ends, one Copy button above it.')}</div>`), 600, 1000)

// 06 themes grid
function themeCard(t) {
  const c = contrast(t.text, t.bg).toFixed(1)
  const g = contrast(t.gear, t.bg).toFixed(1)
  const s1 = contrast(t.s1, t.bg).toFixed(1)
  const s2 = contrast(t.s2, t.bg).toFixed(1)
  const gr = contrast(t.green, t.bg).toFixed(1)
  const label = `<b>${t.name}</b> · ${t.kind} · ${t.status === 'existing' ? 'existing' : `<b style="color:#B4532A">${t.status}</b>`}<br>Text ${c}:1 · gear ${g}:1 · speakers ${s1}:1 / ${s2}:1 · [ Saved ] green ${gr}:1<br>bg ${t.bg} · text ${t.text}`
  return fig(mainCaptioning('p', t), label)
}
add('06-themes.png', 'Themes: 3 light, 3 dark',
  board('6 · Themes: 3 light and 3 dark', 'Light: Paper (existing), Sea Glass and Peach. Dark, revised for older eyes: Bright (yellow on black) is gone, and no dark theme uses pure black behind or pure white text. Charcoal (soft grey) replaces Classic, Night is softened, Harbor (deep teal) is new. Every pair is at or above 7:1 (AAA); numbers are computed.',
    `<div class="row">${THEMES.filter((t) => t.kind === 'light').map(themeCard).join('')}</div><div class="row">${THEMES.filter((t) => t.kind === 'dark').map(themeCard).join('')}</div>`), 1400, 2060)

// 07 (button styles A/B/C) is superseded by 10, the A vs C comparison. [ Save ] / [ New ] are retro text by spec.

// 08 settings: no borders, no boxes, one thin line between sections, on the theme's own background
function settingsSheet(t = theme) {
  const line = t.kind === 'light' ? 'rgba(20,20,25,.12)' : 'rgba(236,230,217,.16)'
  const muted = t.kind === 'light' ? '#56625f' : '#B9B3A6'
  let first = true
  const sec = (title, body, note = '') => {
    const sep = first ? '' : `border-top:1px solid ${line};`
    first = false
    return `<div style="${sep}padding:18px 4px 16px"><div style="font-size:14px;font-weight:800;letter-spacing:.04em;color:${muted};margin-bottom:12px">${title}</div>${body}${note ? `<div style="font-size:13px;color:${muted};margin-top:10px;line-height:1.4">${note}</div>` : ''}</div>`
  }
  const swatches = THEMES.map((x, i) => `<div style="display:flex;flex-direction:column;align-items:center;gap:5px"><div style="width:46px;height:46px;border-radius:15px;background:${x.bg};display:grid;place-items:center;font-weight:800;color:${x.text};box-shadow:0 1px 3px rgba(0,0,0,.18)">Aa</div><div style="font-size:11px;font-weight:600;color:${t.text}">${x.name}</div><div style="height:16px">${(t.id === x.id) ? CHECK(t.gear, 16) : ''}</div></div>`).join('')
  const fontRow = (name, family, sel, tag = '') => `<div style="display:flex;justify-content:space-between;align-items:center;padding:9px 0;color:${t.text}"><span style="font-family:${family};font-size:18px">${name}${tag}</span>${sel ? CHECK(t.gear, 22) : ''}</div>`
  const softFill = t.kind === 'light' ? 'rgba(20,20,25,.07)' : 'rgba(236,230,217,.10)'
  const pill = (s, on) => `<span style="padding:9px 14px;border-radius:16px;font-weight:700;font-size:15px;${on ? `background:${t.text};color:${t.bg}` : `background:${softFill};color:${t.text}`}">${s}</span>`
  const sizeBtn = (s, fs) => `<div class="btn" style="flex:1;height:56px;border-radius:18px;font-size:${fs}px;background:${softFill};color:${t.text}">${s}</div>`
  const link = (s) => `<div style="padding:7px 0;font-weight:600;color:${t.gear}">${s}</div>`
  const body = `
    <div style="display:flex;justify-content:space-between;align-items:center;color:${t.text}"><div style="font-size:24px;font-weight:800">Settings</div><div style="font-weight:700;color:${t.gear}">Done</div></div>
    <div style="margin:16px 4px 6px;font-family:'OpenDyslexic';font-size:19px;line-height:1.45;color:${t.text}">Preview: Let's book a table for seven.</div>
    ${sec('Colors', `<div style="display:flex;justify-content:space-between">${swatches}</div>`)}
    ${sec('Size', `<div style="display:flex;gap:16px">${sizeBtn('A−', 22)}${sizeBtn('A+', 26)}</div>`)}
    ${sec('Lettering', fontRow('Easy to read', "'OpenDyslexic'", true, ` <span style="font-family:system-ui,BlinkMacSystemFont,sans-serif;font-size:12px;font-weight:700;color:${muted}">· default</span>`) + fontRow('Standard', 'system-ui,BlinkMacSystemFont,Helvetica,sans-serif', false) + fontRow('Rounded', "ui-rounded,'SF Pro Rounded',system-ui,sans-serif", false) + fontRow('Serif', 'Georgia,serif', false) + fontRow('Typewriter', 'Menlo,monospace', false), 'Easy to read is OpenDyslexic, a font made for people with dyslexia.')}
    ${sec("Stop when it's quiet", `<div style="display:flex;gap:8px;flex-wrap:wrap">${pill('5 min', true)}${pill('15 min')}${pill('30 min')}${pill('Never')}</div>`)}
    ${sec('Saved', `<div style="display:flex;justify-content:space-between;font-weight:600;color:${t.text}"><span>Saved conversations</span><span style="color:${muted}">3 ›</span></div>`, 'Saved conversations are deleted after 30 days.')}
    ${sec('How to use Seal', `<div class="btn" style="width:100%;height:54px;border-radius:27px;font-size:17px;${primaryStyle(t)}">Show how to use Seal</div>`)}
    ${sec('About', link('Privacy policy') + link('Help and contact') + link('Credits'))}
  `
  return `<div style="width:402px;background:${t.bg};border-radius:40px;padding:26px 20px 30px;box-shadow:0 0 0 10px #1b1d1f,0 18px 40px rgba(0,0,0,.25)">${body}</div>`
}
add('08-settings.png', 'Settings after cleanup',
  board('8 · Settings after cleanup', 'No borders or boxes anywhere: Settings sits on the theme\'s own background so it feels like the same screen, with one thin line between sections. The preview has no border. Text size is two buttons, A− and A+, as in today\'s app. Removed: Words and names, the Speaker labels explainer, and the Conversation section (Copy all / Share), which highlight-and-copy covers. Saved has the 30-day note; one button replays the how-to-use tour.',
    `<div class="row">${fig(settingsSheet(), '<b>Light (Paper).</b> Whole sheet, top to bottom.')}${fig(settingsSheet(T.night), '<b>Dark (Night).</b> Same sheet in a dark theme.')}</div>`), 1000, 1800)

// 09 interactive tour on the real screen
function spot(x, y, w, h, r) {
  return `<div style="position:absolute;left:${x}px;top:${y}px;width:${w}px;height:${h}px;border-radius:${r}px;box-shadow:0 0 0 2000px rgba(12,20,20,.62);z-index:40;pointer-events:none"></div>`
}
function coach(text, sub, pos, step, n = 6, last = false) {
  const dots = Array.from({ length: n }, (_, i) => `<span style="width:${i + 1 === step ? 18 : 7}px;height:7px;border-radius:4px;background:${i + 1 === step ? '#0F5C55' : '#CFC6B5'}"></span>`).join('')
  return `<div style="position:absolute;left:20px;right:20px;${pos};z-index:45;background:#FFFDF6;border-radius:22px;padding:16px 18px;color:#141419;box-shadow:0 10px 30px rgba(0,0,0,.25)">
    <div style="font-size:19px;font-weight:800;line-height:1.3">${text}</div>
    <div style="font-size:15px;line-height:1.4;color:#45524f;margin-top:6px">${sub}</div>
    <div style="display:flex;justify-content:space-between;align-items:center;margin-top:12px"><span style="display:flex;gap:5px">${dots}</span><span style="font-size:15px;font-weight:700;color:#0F5C55">‹ Back &nbsp; ${last ? 'Done ✓' : 'Next ›'}</span></div></div>`
}
const skip = `<div style="position:absolute;right:22px;top:58px;z-index:46;font-weight:800;font-size:17px;color:#FFFDF6">Skip tour</div>`
const hello = [{ s: 1, t: 'Hi! Can you read what I\'m saying?' }]
function tour(step) {
  const t = theme
  let inner = ''
  if (step === 1) inner = topbar(t) + startBtn(t) + spot(14, 768, 374, 72, 36)
    + coach('Tap Start captions', 'Put the phone on the table between you and the people talking. Go ahead, tap it.', 'bottom:150px', 1)
  if (step === 2) inner = topbar(t) + listeningStatus(t) + captionsHTML(t, { lines: hello }) + stopDot(t) + spot(14, 126, 374, 126, 18)
    + coach('Say something', 'Your words show up here as people talk. Each new voice gets its own label.', 'top:290px', 2)
  if (step === 3) inner = topbar(t) + listeningStatus(t) + captionsHTML(t, { lines: hello }) + stopDot(t) + spot(318, 776, 72, 72, 36)
    + coach('Tap X to pause', 'Nothing is lost. Start captions carries on where you left off.', 'bottom:130px', 3)
  if (step === 4) inner = topbar(t) + pausedStatus(t) + captionsHTML(t, { lines: hello }) + dimLayer(t) + saveNew(t, 'save', 330) + startBtn(t) + spot(118, 318, 166, 52, 14)
    + coach('Tap [ Save ] to keep it', 'Saved conversations stay for 30 days. [ New ] starts a fresh one.', 'top:440px', 4)
  if (step === 5) inner = topbar(t) + pausedStatus(t) + `<div class="captions" style="color:${t.text}"><div><div class="spk" style="color:${t.s1}">Speaker 1</div>Hi! Can you read <span class="sel" style="background:rgba(31,153,139,.30)">what I'm saying?</span></div></div>` + startBtn(t) + spot(14, 134, 374, 120, 16)
    + `<div class="btn" style="position:absolute;left:50%;transform:translateX(-50%);top:266px;z-index:44;height:46px;padding:0 24px;border-radius:23px;font-size:18px;background:${t.text};color:${t.bg}">Copy</div>`
    + coach('Hold on words to copy them', 'Press and hold, stretch the selection, then tap Copy.', 'top:340px', 5)
  if (step === 6) inner = topbar(t) + pausedStatus(t) + captionsHTML(t, { lines: hello }) + startBtn(t) + spot(14, 66, 60, 60, 30)
    + coach('Make it yours', 'The gear changes colors, text size and lettering. You can take this tour again there.', 'top:150px', 6, 6, true)
  return phone('p', t, inner + (step === 6 ? '' : skip))
}
add('09-how-to-use-intro.png', 'How-to-use tour on the real screen',
  board('9 · How to use Seal: a tour on the real screen', 'No instruction cards: the tour happens on the real main screen. A spotlight sits on the real control and each step moves on when she actually does it (taps Start, talks, taps X, taps [ Save ], holds words, finds the gear). Fast: Skip tour at any time, or Next to move on without doing it. Slow: no timers; Back goes to the step before. Replays from Settings → Show how to use Seal.',
    `<div class="row">${[1, 2, 3, 4, 5, 6].map((n) => fig(tour(n), ['<b>1.</b> Spotlight on the real Start button.', '<b>2.</b> Captions appear as she talks.', '<b>3.</b> Spotlight on the real X.', '<b>4.</b> Paused: spotlight on [ Save ].', '<b>5.</b> Hold words, then Copy.', '<b>6.</b> The gear; Done ends the tour.'][n - 1])).join('')}</div>`), 2560, 1050)

// 10 button style comparison: A (gummy lip) vs C (outlined cream), light and dark, resting and pressed
function cmpButton(opt, t, pressed) {
  if (opt === 'A') {
    const sq = pressed ? `transform:scaleX(1.06) scaleY(.88) translateY(4px);box-shadow:0 2px 0 ${lipColor(t.text)};` : ''
    return `<div class="btn start" style="width:250px;${primaryStyle(t)}${sq}">Start captions</div>`
  }
  const light = t.kind === 'light'
  const fill = light ? (pressed ? '#F3E1BC' : BRAND.cream) : (pressed ? 'rgba(242,221,181,.22)' : 'rgba(242,221,181,.10)')
  const edge = light ? BRAND.deep : '#F2DDB5'
  const sq = pressed ? 'transform:scaleX(1.08) scaleY(.9);' : ''
  return `<div class="btn start" style="width:250px;background:${fill};color:${edge};border:3px solid ${edge};${sq}">Start captions</div>`
}
function cmpPanel(opt, t) {
  const m = t.kind === 'light' ? '#5c6a68' : '#B9B3A6'
  return `<div style="background:${t.bg};border-radius:28px;padding:28px 22px;display:flex;flex-direction:column;align-items:center;gap:16px;width:300px">
    ${cmpButton(opt, t, false)}<div style="font-size:13px;font-weight:700;color:${m}">Resting</div>
    ${cmpButton(opt, t, true)}<div style="font-size:13px;font-weight:700;color:${m}">Pressed (squished)</div></div>`
}
const cmpText = {
  A: ['<b>Looks:</b> a solid, filled button in the theme\'s text color with a darker flat "lip" underneath, like a chunky key.', '<b>When pressed:</b> it sinks onto its lip and squashes wider and shorter, then bounces back. The press is easy to see.', '<b>For older eyes:</b> the strongest, most obvious button on the screen: big solid shape, highest contrast. Can feel a little heavy.'],
  C: ['<b>Looks:</b> a light cream button with a thick outline (deep teal on light themes; on dark themes a cream outline and cream text). Calmer, more "paper".', '<b>When pressed:</b> the fill darkens and it squashes, then bounces back. Softer, less dramatic than A.', '<b>For older eyes:</b> gentler and less glaring, still clearly a button thanks to the thick outline. The label looks a bit lighter than A\'s.'],
}
add('10-button-compare-A-vs-C.png', 'Button style: A vs C',
  board('10 · Start button: A (gummy lip) vs C (outlined cream)', 'The same Start captions button in both styles, resting and pressed, in a light theme (Paper) and a dark theme (Night). Pick one in Decisions; the other screens show A so you can see one in context. [ Save ] and [ New ] stay retro text either way.',
    ['A', 'C'].map((o) => `<div class="row" style="align-items:center"><div style="font-size:22px;font-weight:800;color:#0F3F3C;width:40px">${o}</div>${cmpPanel(o, T.paper)}${cmpPanel(o, T.night)}<div class="cap" style="max-width:420px;font-size:15px">${cmpText[o].map((x) => `<div style="margin-bottom:8px">${x}</div>`).join('')}</div></div>`).join('')), 1400, 900)

// 11 launch hand-off (connects to #99): the seal's freeze frame hands off into this main screen
const RIG = fs.readFileSync(path.join(SRC, 'seal-rig.svg'), 'utf8').replace(/<rect id="bg"[^>]*\/>/, '').replace(/<!--[\s\S]*?-->/g, '')
const sealSVG = (size, extra = '') => RIG.replace('<svg ', `<svg style="width:${size}px;height:${size}px;${extra}" `).replace(/ width="1024" height="1024"/, '')
const LAUNCH = '#1F998B'
function launchFrame(kind, k) {
  const t = theme
  const bar = (op = 1) => `<div style="position:absolute;left:96px;right:96px;bottom:250px;height:8px;border-radius:4px;background:rgba(251,232,193,.35);opacity:${op}"><div style="width:100%;height:100%;border-radius:4px;background:#FBE8C1"></div></div>`
  const main = (op) => `<div style="opacity:${op}">${topbar(t)}</div>`
  if (k === 0) return phone('p', { ...t, bg: LAUNCH, text: '#FBE8C1' }, `<div style="position:absolute;left:50%;top:300px;transform:translateX(-50%)">${sealSVG(220)}</div>${bar()}`)
  if (kind === 'glide') {
    if (k === 1) return phone('p', { ...t, bg: LAUNCH, text: '#FBE8C1' }, `<div style="position:absolute;left:50%;top:620px;transform:translateX(-50%)">${sealSVG(110)}</div>${bar(0.3)}`)
    if (k === 2) return phone('p', t, `<div style="position:absolute;inset:0;background:${LAUNCH};opacity:.35"></div>${main(0.7)}<div class="btn start" style="position:absolute;left:50%;transform:translateX(-50%) scale(.55);bottom:40px;width:362px;z-index:30;${primaryStyle(t)}"></div><div style="position:absolute;left:50%;bottom:44px;transform:translateX(-50%);z-index:31">${sealSVG(56)}</div>`)
    return phone('p', t, topbar(t) + startBtn(t))
  }
  if (k === 1) return phone('p', { ...t, bg: LAUNCH, text: '#FBE8C1' }, `<div style="position:absolute;left:50%;top:600px;transform:translateX(-50%) rotate(28deg)">${sealSVG(200)}</div>${bar(0.3)}`)
  if (k === 2) return phone('p', t, `<div style="position:absolute;left:0;right:0;top:0;height:46%;background:${LAUNCH}"></div><div style="position:absolute;left:0;right:0;top:46%;height:20px;background:${LAUNCH};border-radius:0 0 50% 50%/0 0 100% 100%"></div>${startBtn(t)}`)
  return phone('p', t, topbar(t) + startBtn(t))
}
add('11-launch-handoff.png', 'Launch hand-off into the main screen',
  board('11 · How the launch animation (#99) hands off into this screen', 'The end of the launch: the seal holds its freeze-frame pose on the green launch screen with the progress bar full, waits 0.75 s, then hands off into the new main screen from these mock-ups (Start captions at the bottom middle, gear top-left). Two ways, pick one in Decisions. #99 gets updated to match whatever is approved here.',
    `<div style="font-size:18px;font-weight:800;color:#0F3F3C">Glide: the seal shrinks and glides down into the Start button, which grows out of it</div>
    <div class="row">${[0, 1, 2, 3].map((k) => fig(launchFrame('glide', k), ['<b>1.</b> Freeze frame, bar full, 0.75 s hold.', '<b>2.</b> Seal shrinks and glides down.', '<b>3.</b> It lands in the Start spot; the button grows out of it as the main screen fades in.', '<b>4.</b> Ready: the main screen.'][k])).join('')}</div>
    <div style="font-size:18px;font-weight:800;color:#0F3F3C;margin-top:10px">Dive: the seal dives down and the main screen washes up</div>
    <div class="row">${[0, 1, 2, 3].map((k) => fig(launchFrame('dive', k), ['<b>1.</b> Freeze frame, bar full, 0.75 s hold.', '<b>2.</b> Seal tips forward and dives down.', '<b>3.</b> The main screen washes up from below as the green drains away.', '<b>4.</b> Ready: the main screen.'][k])).join('')}</div>`), 1880, 2050)

// ---------- render ----------
// The playwright-core here may be newer than the cached browser build; point it at whichever Chromium exists.
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

// contrast report for the README
console.log(JSON.stringify(THEMES.map((t) => ({ name: t.name, text: contrast(t.text, t.bg).toFixed(2), gear: contrast(t.gear, t.bg).toFixed(2), s1: contrast(t.s1, t.bg).toFixed(2), s2: contrast(t.s2, t.bg).toFixed(2), green: contrast(t.green, t.bg).toFixed(2) }))))
