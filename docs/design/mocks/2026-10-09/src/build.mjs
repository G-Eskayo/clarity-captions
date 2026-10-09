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
// Dark: the three existing dark presets (Classic, Bright, Night), unchanged colors. Light: the existing Paper plus
// two new ones in the icon's palette. Gear color is chosen per theme (non-text UI, must be >= 3:1; we aim higher).
const THEMES = [
  { id: 'paper', name: 'Paper', kind: 'light', bg: '#FAF5E6', text: '#141419', gear: '#14514B', s1: '#14514B', s2: '#7A350C', status: 'existing' },
  { id: 'seaglass', name: 'Sea Glass', kind: 'light', bg: '#DCEFEA', text: '#0D2F2C', gear: '#0B4842', s1: '#0B4842', s2: '#6E2E0A', status: 'new' },
  { id: 'peach', name: 'Peach', kind: 'light', bg: '#FBE8D2', text: '#2B1A10', gear: '#6E2E0A', s1: '#0B4842', s2: '#6E2E0A', status: 'new' },
  { id: 'classic', name: 'Classic', kind: 'dark', bg: '#000000', text: '#FFFFFF', gear: '#FFFFFF', s1: '#7FD8CC', s2: '#F4C27E', status: 'existing' },
  { id: 'bright', name: 'Bright', kind: 'dark', bg: '#000000', text: '#FFE633', gear: '#FFE633', s1: '#7FD8CC', s2: '#F4A27E', status: 'existing' },
  { id: 'night', name: 'Night', kind: 'dark', bg: '#0D1226', text: '#D9E6FF', gear: '#9DB8FF', s1: '#7FD8CC', s2: '#F4C27E', status: 'existing' },
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

function topbar(t, center) {
  return `<div class="topbar"><div class="gear">${GEAR(t.gear)}</div>${center}</div>`
}
const listeningStatus = (t) => `<div class="status" style="color:${t.text}"><span class="dot" style="background:${t.text}"></span>Listening</div>`
const pausedStatus = (t) => `<div class="status" style="color:${t.text}">Paused</div>`
const stopDot = (t) => `<div class="stopdot btn" style="${primaryStyle(t)}">${XICON(t.bg)}</div>`
const startBtn = (t, label = 'Start captions') => `<div class="btn start" style="${primaryStyle(t)}">${label}</div>`

function dimLayer(t, opacity = 1) {
  const c = t.kind === 'light' ? 'rgba(20,30,30,.42)' : 'rgba(0,0,0,.55)'
  return `<div class="dim" style="background:${c};opacity:${opacity}"></div>`
}
function saveNew(t, saveState = 'save', top = 150) {
  let save
  if (saveState === 'save') save = `<div class="btn small" style="${secondaryStyle(t)}">SAVE</div>`
  else if (saveState === 'check') save = `<div class="btn" style="width:64px;height:64px;border-radius:18px;background:${GREEN.fill};box-shadow:0 5px 0 #11502F">${CHECK('#fff', 36)}</div>`
  else save = `<div class="btn small" style="background:${GREEN.fill};color:#fff;box-shadow:0 5px 0 #11502F">${CHECK('#fff', 22)} SAVED</div>`
  const neu = `<div class="btn small" style="${secondaryStyle(t)}">NEW</div>`
  return `<div class="overlay-buttons" style="top:${top}px"><div style="height:64px;display:grid;place-items:center">${save}</div>${neu}</div>`
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
  const center = `<div style="display:flex;flex-direction:column;align-items:center;gap:6px">${stopDot(t)}</div>`
  return phone(orient, t, topbar(t, center) + listeningStatus(t) + captionsHTML(t, { lines: orient === 'l' ? LINES.slice(2) : LINES }))
}
function paused(orient, t = theme, { saveState = 'save', dimOpacity = 1, hideButtons = false } = {}) {
  const center = startBtn(t)
  const top = orient === 'p' ? 178 : 112
  const inner = topbar(t, center) + pausedStatus(t) + captionsHTML(t, { lines: orient === 'l' ? LINES.slice(2, 6) : LINES.slice(0, 6) })
    + dimLayer(t, dimOpacity) + (hideButtons ? '' : saveNew(t, saveState, top))
  // The top bar (gear + Start) stays above the dim.
  return phone(orient, t, inner.replace('<div class="topbar">', '<div class="topbar" style="z-index:20">'))
}

const PAGES = []
const add = (file, title, html, w, h) => PAGES.push({ file, title, html: doc(title, html, w, h), w, h })

// 01 main screen while captioning
add('01-main-captioning.png', 'Main screen while captioning',
  board('1 · Main screen while captioning', 'Gear in the top-left corner: icon only, no label, no background, colored for the theme. Stop keeps today\'s behavior (the big button shrinks into a small circle with an X) but now sits at the top middle, because Start lives there. Captions in the dyslexia-friendly font (the new default). Theme shown: Paper.',
    `<div class="row">${fig(mainCaptioning('p'), '<b>Portrait.</b> Top row: gear left, small Stop circle in the middle. "Listening" with its dot under it.')}${fig(mainCaptioning('l'), '<b>Landscape.</b> Same top row; captions use the full width below it.')}</div>`), 1400, 1000)

// 02 paused
add('02-paused-save-new.png', 'Paused: Start, Save, New',
  board('2 · Paused (after pressing X)', 'Start captions comes back at the top middle exactly as it works today. The captions dim, and SAVE with NEW stacked under it fade in under Start. Pressing Start captions fades the dim and both buttons back to clear and the same conversation carries on.',
    `<div class="row">${fig(paused('p'), '<b>Portrait.</b> Dim covers the captions only; gear and Start stay on top.')}${fig(paused('l'), '<b>Landscape.</b> SAVE and NEW stack under Start in the middle.')}</div>`), 1400, 1000)

// 03 save animation strip
add('03-save-animation.png', 'Save animation',
  board('3 · Save animation (3 frames, about 0.8 s total)', 'Tap SAVE: the button squishes, turns into a green check box, then grows into a green SAVED. If new captions arrive later (content changes, not time passing), it turns back into SAVE so she can save again; saving again updates the same saved conversation.',
    `<div class="row">${fig(paused('p', theme, { saveState: 'save' }), '<b>Frame 1.</b> SAVE, as it appears when paused.')}${fig(paused('p', theme, { saveState: 'check' }), '<b>Frame 2.</b> Squishes into a green check box.')}${fig(paused('p', theme, { saveState: 'saved' }), '<b>Frame 3.</b> Grows into a green SAVED and stays.')}</div>`), 1400, 1000)

// 04 dim cleared + hold on empty space
function clearedFrame(withTouch) {
  const t = theme
  const hint = `<div class="chip" style="bottom:56px;background:${t.text};color:${t.bg}">Hold on empty space to bring back Save and New</div>`
  let inner = topbar(t, startBtn(t)) + pausedStatus(t) + captionsHTML(t, { lines: LINES.slice(0, 6) })
  if (!withTouch) inner += hint
  else inner += dimLayer(t, 0.45) + saveNew(t, 'save', 178).replace('style="top:178px"', 'style="opacity:.5;top:178px"')
    + `<div class="touch" style="left:280px;bottom:44px;background:rgba(31,153,139,.35);box-shadow:0 0 0 10px rgba(31,153,139,.18),0 0 0 22px rgba(31,153,139,.08)"></div>`
    + `<div class="anno" style="left:24px;bottom:40px;max-width:230px">Press and hold on empty space: the dim and buttons fade back in</div>`
  return phone('p', t, inner)
}
add('04-dim-cleared-and-back.png', 'Dim cleared for scrolling and copying',
  board('4 · Clearing the dim to scroll and copy', 'While paused, one tap on the dimmed area fades the dim and SAVE / NEW away, so she can scroll and select text. Start stays put. Press and hold on empty space (not on words) brings them back. A press-and-hold on words selects text instead (see 5). Proposed, for your sign-off.',
    `<div class="row">${fig(paused('p'), '<b>1.</b> Paused, dimmed.')}${fig(clearedFrame(false), '<b>2.</b> One tap on the dim: clear. A small hint shows the first few times.')}${fig(clearedFrame(true), '<b>3.</b> Press and hold on empty space: dim and buttons fade back in.')}</div>`), 1400, 1000)

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
  const inner = topbar(t, startBtn(t)) + pausedStatus(t) + captionsHTML(t, { lines: LINES.slice(0, 6), selection: sel })
    + `<div id="hS" class="handle s" style="background:#1F998B;height:32px"></div><div id="hE" class="handle e" style="background:#1F998B;height:32px"></div>`
    + `<script>addEventListener('load',()=>document.fonts.ready.then(()=>{const scr=document.querySelector('#hS').parentElement.getBoundingClientRect();for(const[m,h]of[['selS','hS'],['selE','hE']]){const r=document.getElementById(m).getBoundingClientRect();const el=document.getElementById(h);el.style.left=(r.left-scr.left-1)+'px';el.style.top=(r.top-scr.top+2)+'px'}}))</script>`
    + `<div class="btn" style="position:absolute;left:50%;transform:translateX(-50%);top:330px;z-index:30;height:50px;padding:0 26px;border-radius:25px;font-size:19px;background:${t.text};color:${t.bg};box-shadow:0 5px 0 ${lipColor(t.text)}"><svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="${t.bg}" stroke-width="2.4"><rect x="9" y="9" width="11" height="11" rx="2.5"/><path d="M5 15V6a2 2 0 0 1 2-2h9"/></svg>Copy</div>`
  return phone('p', t, inner)
}
add('05-copy.png', 'Copy: only a Copy button',
  board('5 · Copying text', 'Press and hold on words to select, drag the handles across lines. About half a second after the selection stops changing, only a Copy button appears (no Look Up, Share, or other menu items). The handles still work after Copy appears.',
    `<div class="row">${fig(copyFrame(), '<b>Selection across several lines</b>, handles at both ends, one Copy button above it.')}</div>`), 600, 1000)

// 06 themes grid
function themeCard(t) {
  const c = contrast(t.text, t.bg).toFixed(1)
  const g = contrast(t.gear, t.bg).toFixed(1)
  const s1 = contrast(t.s1, t.bg).toFixed(1)
  const s2 = contrast(t.s2, t.bg).toFixed(1)
  const label = `<b>${t.name}</b> · ${t.kind} · ${t.status === 'new' ? '<b style="color:#B4532A">new</b>' : 'existing'}<br>Text ${c}:1 · gear ${g}:1 · speaker labels ${s1}:1 / ${s2}:1<br>bg ${t.bg} · text ${t.text} · gear ${t.gear}`
  return fig(mainCaptioning('p', t), label)
}
add('06-themes.png', 'Themes: 3 light, 3 dark',
  board('6 · Themes: 3 light and 3 dark', 'Light: Paper (existing) plus two new ones in the icon\'s palette, Sea Glass and Peach. Dark: the three existing ones (Classic, Bright, Night), unchanged. Every caption color pair is at or above 7:1 (AAA); numbers are computed. Gear color is picked per theme. Open: you asked for relaxing colors, so Bright (yellow on black) could be swapped for a softer dark one; kept for now because nothing said to remove it.',
    `<div class="row">${THEMES.filter((t) => t.kind === 'light').map(themeCard).join('')}</div><div class="row">${THEMES.filter((t) => t.kind === 'dark').map(themeCard).join('')}</div>`), 1400, 2060)

// 07 button styles A/B/C
function styleCell(opt, pressed) {
  const t = theme
  let start, save
  const squish = pressed ? 'transform:scaleX(1.06) scaleY(.88) translateY(4px);' : ''
  if (opt === 'A') {
    start = `<div class="btn start" style="${primaryStyle(t)}${pressed ? `box-shadow:0 2px 0 ${lipColor(t.text)};` : ''}${squish}">Start captions</div>`
    save = `<div class="btn small" style="${secondaryStyle(t)}${pressed ? 'box-shadow:0 2px 0 #CFC6B5;' : ''}${squish}">SAVE</div>`
  } else if (opt === 'B') {
    const sq = pressed ? 'transform:scale(.92);' : ''
    start = `<div class="btn start" style="background:${BRAND.teal};color:#fff;background-image:linear-gradient(${BRAND.teal} 0 55%, #1A8a7d 55% 100%);${sq}">Start captions</div>`
    save = `<div class="btn small" style="background:${BRAND.cream};color:${BRAND.deep};background-image:linear-gradient(${BRAND.cream} 0 55%, #F2DDB5 55% 100%);${sq}">SAVE</div>`
  } else {
    const sq = pressed ? 'transform:scaleX(1.08) scaleY(.9);' : ''
    start = `<div class="btn start" style="background:${pressed ? '#F3E1BC' : BRAND.cream};color:${BRAND.deep};border:3px solid ${BRAND.deep};${sq}">Start captions</div>`
    save = `<div class="btn small" style="background:${pressed ? '#ECE6DA' : '#fff'};color:${BRAND.deep};border:3px solid ${BRAND.deep};${sq}">SAVE</div>`
  }
  return `<div style="background:${t.bg};border-radius:28px;padding:30px 28px;display:flex;flex-direction:column;align-items:center;gap:20px;width:300px;box-shadow:0 0 0 1px #d8d0bf">${start}${save}<div style="font-size:13px;font-weight:700;color:#5c6a68">${pressed ? 'Pressed (squished)' : 'Resting'}</div></div>`
}
const styleBlurb = {
  A: '<b>A · Gummy lip.</b> Solid flat fill in the theme\'s text color with a darker flat "lip" under it. Pressing sinks it onto the lip and squashes it wider and shorter, like a gummy.',
  B: '<b>B · Two-tone jelly.</b> Brand teal (and cream for secondary), a flat lighter top half. Pressing shrinks the whole button evenly (scale 0.92) and springs back. Note: white on brand teal is 3.4:1, enough only for large bold text, so B would darken the teal in the app.',
  C: '<b>C · Outlined cream.</b> Cream fill, thick deep-teal outline. Pressing darkens the fill and squashes it. The quietest of the three.',
}
add('07-button-styles.png', 'Flat and gummy button styles',
  board('7 · Flat and gummy buttons: pick A, B or C', 'Same buttons in three styles, resting and pressed. The squish springs back with a little bounce (about 0.25 s). The other screens use A so you can see it in context.',
    ['A', 'B', 'C'].map((o) => `<div class="row" style="align-items:center">${styleCell(o, false)}${styleCell(o, true)}<div class="cap" style="max-width:420px">${styleBlurb[o]}</div></div>`).join('')), 1400, 600)

// 08 settings
function settingsSheet() {
  const t = theme
  const sec = (title, body, note = '') => `<div style="margin-top:22px"><div style="font-size:13px;font-weight:800;letter-spacing:.06em;text-transform:uppercase;color:#5c6a68;margin:0 6px 8px">${title}</div><div style="background:#fff;border-radius:22px;padding:14px 16px">${body}</div>${note ? `<div style="font-size:13px;color:#5c6a68;margin:8px 8px 0;line-height:1.4">${note}</div>` : ''}</div>`
  const swatches = THEMES.map((x, i) => `<div style="display:flex;flex-direction:column;align-items:center;gap:4px"><div style="width:44px;height:44px;border-radius:14px;background:${x.bg};border:${i === 0 ? '3px solid #1F998B' : '1px solid #d0c8b8'};display:grid;place-items:center;font-weight:800;color:${x.text}">Aa</div><div style="font-size:11px;font-weight:600">${x.name}</div></div>`).join('')
  const fontRow = (name, family, sel, tag = '') => `<div style="display:flex;justify-content:space-between;align-items:center;padding:10px 4px;${sel ? '' : 'opacity:.85'}"><span style="font-family:${family};font-size:18px">${name}${tag}</span>${sel ? CHECK('#1F998B', 22) : ''}</div>`
  const pill = (s, on) => `<span style="padding:8px 13px;border-radius:16px;font-weight:700;font-size:14px;${on ? 'background:#0F5C55;color:#fff' : 'background:#EFE9DD'}">${s}</span>`
  const body = `
    <div style="display:flex;justify-content:space-between;align-items:center"><div style="font-size:24px;font-weight:800">Settings</div><div style="font-weight:700;color:#1F6F66">Done</div></div>
    <div style="margin-top:14px;background:${t.bg};border-radius:18px;padding:14px;border:1px solid #e1d9c8;font-family:'OpenDyslexic';font-size:18px;color:${t.text}">Preview: Let's book a table for seven.</div>
    ${sec('Colors', `<div style="display:flex;justify-content:space-between">${swatches}</div>`)}
    ${sec('Size', `<div style="display:flex;justify-content:space-between;align-items:center"><span style="font-weight:800;font-size:18px">A−</span><div style="flex:1;height:6px;background:#E5DED0;border-radius:3px;margin:0 14px;position:relative"><div style="position:absolute;left:45%;top:-9px;width:24px;height:24px;border-radius:50%;background:#0F5C55"></div></div><span style="font-weight:800;font-size:22px">A+</span></div>`)}
    ${sec('Lettering', fontRow('Easy to read', "'OpenDyslexic'", true, ' <span style="font-family:system-ui,BlinkMacSystemFont,sans-serif;font-size:12px;font-weight:700;color:#1F6F66">· default</span>') + fontRow('Standard', 'system-ui,BlinkMacSystemFont,Helvetica,sans-serif', false) + fontRow('Rounded', "ui-rounded,'SF Pro Rounded',system-ui,sans-serif", false) + fontRow('Serif', 'Georgia,serif', false) + fontRow('Typewriter', 'Menlo,monospace', false), 'Easy to read is OpenDyslexic, a font made for people with dyslexia.')}
    ${sec("Stop when it's quiet", `<div style="display:flex;gap:8px;flex-wrap:wrap">${pill('5 min', true)}${pill('15 min')}${pill('30 min')}${pill('Never')}</div>`)}
    ${sec('Conversation', `<div style="padding:6px 2px;font-weight:600;color:#1F6F66">Copy all text</div><div style="padding:6px 2px;font-weight:600;color:#1F6F66">Share as text</div>`)}
    ${sec('Saved', `<div style="display:flex;justify-content:space-between;font-weight:600"><span>Saved conversations</span><span style="color:#5c6a68">3 ›</span></div>`, 'Saved conversations are deleted after 30 days.')}
    ${sec('How to use Seal', `<div class="btn" style="width:100%;height:50px;border-radius:25px;font-size:17px;background:${t.text};color:${t.bg};box-shadow:0 5px 0 ${lipColor(t.text)}">Show how to use Seal</div>`)}
    ${sec('About', `<div style="padding:6px 2px;font-weight:600">Privacy policy</div><div style="padding:6px 2px;font-weight:600">Help and contact</div><div style="padding:6px 2px;font-weight:600">Credits</div>`)}
  `
  return `<div style="width:402px;background:#F4F0E8;border-radius:40px;padding:26px 18px 30px;box-shadow:0 0 0 10px #1b1d1f,0 18px 40px rgba(0,0,0,.25)">${body}</div>`
}
add('08-settings.png', 'Settings after cleanup',
  board('8 · Settings after cleanup', 'Removed: Words and names, and the Speaker labels explainer. Lettering gets the dyslexia-friendly font, selected as the default (shown here as "Easy to read"; the name is a proposal). Saved has the 30-day note. New: one button to replay the how-to-use intro. Shown as the whole scrolling sheet.',
    `<div class="row">${fig(settingsSheet(), '<b>Whole sheet, top to bottom.</b> Section order kept from today, minus the two removed sections, plus "How to use Seal".')}</div>`), 600, 1800)

// 09 intro
function introFrame(n, title, body, demo, last = false) {
  const t = theme
  const dots = [1, 2, 3, 4].map((i) => `<span style="width:${i === n ? 22 : 9}px;height:9px;border-radius:5px;background:${i === n ? BRAND.deep : '#CFC6B5'}"></span>`).join('')
  const inner = `
    <div style="display:flex;justify-content:flex-end;height:44px;align-items:center"><span style="font-weight:700;color:${BRAND.deep};font-size:17px">${last ? '' : 'Skip'}</span></div>
    <div style="height:400px;margin-top:10px;border-radius:30px;background:#fff;position:relative;overflow:hidden">${demo}</div>
    <div style="margin-top:26px;text-align:center;font-size:27px;font-weight:800;color:${t.text}">${title}</div>
    <div style="margin-top:10px;text-align:center;font-size:17px;line-height:1.45;color:#3d4b4a;padding:0 12px">${body}</div>
    <div style="position:absolute;bottom:110px;left:0;right:0;display:flex;gap:6px;justify-content:center">${dots}</div>
    <div style="position:absolute;bottom:40px;left:20px;right:20px;display:flex;justify-content:center"><div class="btn start" style="width:100%;${primaryStyle(t)}">${last ? 'Start using Seal' : 'Next'}</div></div>`
  return phone('p', t, inner)
}
const miniCaps = (t) => `<div style="font-family:OpenDyslexic;font-size:16px;line-height:1.5;padding:0 18px;color:${t.text}"><div class="spk" style="color:${t.s1}">Speaker 1</div>Let's book a table for seven.</div>`
const demo1 = `<div style="display:flex;flex-direction:column;align-items:center;padding-top:40px;gap:30px">${startBtn(theme)}<div class="touch" style="position:relative;width:60px;height:60px;margin-top:-80px;margin-left:120px;background:rgba(31,153,139,.35);box-shadow:0 0 0 10px rgba(31,153,139,.15)"></div><div style="font-size:14px;font-weight:700;color:#5c6a68">Try it: tap Start</div><div style="align-self:stretch;margin-top:10px">${miniCaps(theme).replace("Let's book a table for seven.","Hi! Can you read what I'm saying?")}</div></div>`
const demo2 = `<div style="padding-top:30px">${miniCaps(theme)}<div style="position:absolute;inset:0;background:rgba(20,30,30,.42)"></div><div style="position:absolute;top:110px;left:0;right:0;display:flex;flex-direction:column;align-items:center;gap:12px">${startBtn(theme)}<div class="btn small" style="${secondaryStyle(theme)}">SAVE</div><div class="btn small" style="${secondaryStyle(theme)}">NEW</div></div></div>`
const demo3 = `<div style="padding-top:60px;font-family:OpenDyslexic;font-size:18px;line-height:1.6;padding-left:20px;padding-right:20px;color:${theme.text}"><div class="spk" style="color:${theme.s1}">Speaker 1</div>Meet us at <span style="background:rgba(31,153,139,.3);border-radius:4px">Luigi's on Fifth</span> around seven.</div><div class="btn" style="position:absolute;top:30px;left:50%;transform:translateX(-50%);height:44px;padding:0 22px;border-radius:22px;font-size:17px;${primaryStyle(theme)}">Copy</div><div style="position:absolute;bottom:24px;left:0;right:0;text-align:center;font-size:14px;font-weight:700;color:#5c6a68">Try it: hold on a word</div>`
const demo4 = `<div style="padding:24px 20px"><div style="display:flex;align-items:center;gap:12px">${GEAR(theme.gear, 40)}<span style="font-weight:700;color:#5c6a68">← this gear</span></div><div style="display:flex;gap:10px;margin-top:40px;justify-content:center">${THEMES.map((x) => `<div style="width:42px;height:42px;border-radius:13px;background:${x.bg};border:1px solid #d0c8b8;display:grid;place-items:center;font-weight:800;color:${x.text}">Aa</div>`).join('')}</div><div style="margin-top:30px;text-align:center;font-family:OpenDyslexic;font-size:22px">A− &nbsp; A+</div></div>`
add('09-how-to-use-intro.png', 'How-to-use intro',
  board('9 · How to use Seal (first run, replay from Settings)', 'Four short cards. Each has a tiny live demo she can try (tap Start, hold a word), or she can ignore it. Fast: Skip at the top, or swipe. Slow: stay on a card as long as she likes, swipe back anytime. The same four cards replay from Settings → "Show how to use Seal".',
    `<div class="row">${fig(introFrame(1, 'Tap Start to see what people say', 'Put the phone on the table between you and the people talking.', demo1), '<b>Card 1.</b> Start.')}${fig(introFrame(2, 'Tap X to pause', 'SAVE keeps this conversation. NEW starts a fresh one. Start carries on where you left off.', demo2), '<b>Card 2.</b> Pause, Save, New.')}${fig(introFrame(3, 'Hold words to copy them', 'Press and hold, stretch the selection, then tap Copy.', demo3), '<b>Card 3.</b> Copy.')}${fig(introFrame(4, 'Make it yours', 'The gear changes colors, text size and lettering. You can watch this again there.', demo4, true), '<b>Card 4.</b> Settings, and the way back to this intro.')}</div>`), 1880, 1050)

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
console.log(JSON.stringify(THEMES.map((t) => ({ name: t.name, text: contrast(t.text, t.bg).toFixed(2), gear: contrast(t.gear, t.bg).toFixed(2), s1: contrast(t.s1, t.bg).toFixed(2), s2: contrast(t.s2, t.bg).toFixed(2) }))))
