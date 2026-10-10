// Round-3 mock-ups (2026-10-10): tour v2 wording (plain, only what isn't obvious), first-run screens, Credits and
// Jump to latest in the v1 look. Helpers copied from ../round2/src/build.mjs. Same look as docs/design/mocks/2026-10-09 (themes, gummy button A, OpenDyslexic captions, retro
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

// --- Tour v2 wording ------------------------------------------------------------------------------------------
// The words are the point of this board. Plain, short, only what isn't obvious. Each step waits for the real action.
const STEPS = 8
const myWords = (t, highlight = false) => `<div class="captions" style="color:${t.text}"><div><div class="spk" style="color:${t.s1}">Speaker 1</div>Hi, is this working? ${highlight ? '<span style="background:#1F998B44;border-radius:4px">' : ''}I can see what I'm saying.${highlight ? '</span>' : ''}</div></div>`
const twoVoices = (t) => `<div class="captions" style="color:${t.text}"><div><div class="spk" style="color:${t.s1}">Speaker 1</div>Hi, is this working? I can see what I'm saying.</div><div><div class="spk" style="color:${t.s2}">Speaker 2</div>Yep, it put me on my own line.</div></div>`
function tour(t, o) {
  const { step, status = 'Ready', title, sub, top = 560, hole = null, start = true, stop = false, mid = '', body = '', dim = true, cleared = false, extra = '' } = o
  const veilCut = !dim ? '' : hole
    ? `<div style="position:absolute;z-index:15;left:${hole[0]}px;top:${hole[1]}px;width:${hole[2]}px;height:${hole[3]}px;border-radius:${hole[4] ?? 32}px;box-shadow:0 0 0 2000px ${t.bg}E6"></div>`
    : `<div style="position:absolute;inset:0;background:${t.bg};opacity:.9;z-index:15"></div>`
  return phone(t, layer(topbar(t, status) + body) + veilCut +
    `<div style="position:absolute;right:22px;top:72px;z-index:25;color:${t.text};font-size:15px;font-weight:700;opacity:.8">Skip tour</div>` +
    `<div style="position:absolute;left:28px;right:28px;top:${top - 34}px;z-index:25;color:${t.text};text-align:center;font-size:14px;font-weight:700;opacity:.55">${step} of ${STEPS}${step > 1 ? ' · ‹ Back' : ''}</div>` +
    `<div style="position:absolute;left:28px;right:28px;top:${top}px;z-index:25;color:${t.text};text-align:center"><div class="say">${title}</div><div class="small" style="opacity:.82;margin-top:6px">${sub}</div>${extra}</div>` +
    (mid ? `<div style="position:absolute;left:0;right:0;top:330px;z-index:20;display:flex;flex-direction:column;align-items:center;gap:22px">${mid}</div>` : '') +
    (start ? startBtn(t) : '') + (stop ? stopDot() : ''))
}
// The drafted words, one entry per screen. "after" screens are the same step once she has done the thing.
const TOUR = (t) => [
  { n: '1', cap: 'Only Start is lit. Nothing else answers.', f: tour(t, { step: 1, title: 'Set the phone flat on the table.', sub: "Between you and whoever's talking. Then tap Start captions.", hole: [16, 790, 370, 72, 36] }) },
  { n: '2', cap: 'Waiting for a voice. After 6 s of quiet, [ Show an example ] appears.', f: tour(t, { step: 2, status: 'Listening', title: 'Say something.', sub: 'Your words show up here as you talk.', top: 330, start: false, stop: true, hole: [16, 130, 370, 120, 20] }) },
  { n: '2, after', cap: 'Her words appeared. A second voice is shown in the example only if the room stays quiet.', f: tour(t, { step: 2, status: 'Listening', title: "That's you.", sub: "Each voice gets its own line and label. Seal goes by the sound of the voice, so it can mix people up. It doesn't know who anyone is.", top: 400, start: false, stop: true, body: twoVoices(t), hole: [16, 130, 370, 230, 20] }) },
  { n: '3', cap: 'Only ✕ is lit.', f: tour(t, { step: 3, status: 'Listening', title: 'Tap ✕ to pause.', sub: 'Nothing gets lost. Start captions picks up where you left off.', start: false, stop: true, body: myWords(t), hole: [312, 784, 76, 76, 38] }) },
  { n: '4', cap: 'Only [ Save ] is lit.', f: tour(t, { step: 4, status: 'Paused', title: 'Tap [ Save ].', sub: 'Keeps it on this phone for 30 days.', body: myWords(t), mid: retro(t, 'Save') + retro(t, 'New'), hole: [110, 318, 182, 56, 12] }) },
  { n: '4, after', cap: '[ ✔ ] → [ Saved ] plays out first. Then these words fade in.', f: tour(t, { step: 4, status: 'Paused', title: 'Saved.', sub: 'It stays green until somebody says something new.', body: myWords(t), mid: retro(t, 'Saved', t.green) + retro(t, 'New'), hole: [110, 318, 182, 56, 12] }) },
  { n: '5', cap: 'The whole dim is lit. A tap clears it.', f: tour(t, { step: 5, status: 'Paused', title: 'Tap anywhere on the dim.', sub: 'It clears so you can read and scroll back.', body: myWords(t), mid: retro(t, 'Saved', t.green) + retro(t, 'New'), top: 600 }) },
  { n: '6', cap: 'Cleared. Holding an empty spot (not words) brings the buttons back.', f: tour(t, { step: 6, status: 'Paused', title: 'Hold an empty spot.', sub: 'The buttons come back.', body: myWords(t), dim: false, top: 600 }) },
  { n: '7', cap: 'Only the gear is lit. Settings fades in; the step ends when she taps the gear again.', f: tour(t, { step: 7, status: 'Paused', title: 'Tap the gear.', sub: 'Colors, text size and lettering. Tap it again to come back.', body: myWords(t), hole: [16, 66, 52, 52, 26] }) },
  { n: '8', cap: 'The only screen with a button to finish. Copy is just mentioned: people already know how to hold and copy.', f: tour(t, { step: 8, status: 'Paused', title: "That's it.", sub: '[ New ] clears the screen for the next conversation. It asks once first.<br><br>Hold on any words to copy them.<br><br>If it goes quiet for a while, captions pause on their own.<br><br>You can replay this in Settings.', top: 380, body: myWords(t), extra: `<div style="margin-top:26px;display:grid;place-items:center">${retro(t, 'Done')}</div>` }) },
]
add('01-tour-v2-wording.png', 'Tour v2 wording',
  board('1 · Tour v2: plain words, only what isn\'t obvious (Paper)', 'Each step waits for her to really do it: Start, talk, ✕, [ Save ], tap the dim, hold an empty spot, the gear. No Next button on any of those. Back and Skip tour stay on every step. Copy and [ New ] aren\'t taught: copy works like every other app, and practising [ New ] would wipe her practice. They\'re mentioned once at the end. The words sit on the dim, no card, fades only.',
    `<div class="row">${TOUR(T.paper).map((s) => fig(s.f, s.cap, s.n)).join('')}</div>`), 2250, 2100)
add('02-tour-v2-night.png', 'Tour v2 wording, dark',
  board('2 · The same tour on a dark theme (Night)', 'Same words, same steps. Shown: the first step, her words, [ Save ], tapping the dim and the last screen.',
    `<div class="row">${TOUR(T.night).filter((_, i) => [0, 2, 4, 6, 9].includes(i)).map((s) => fig(s.f, s.cap, s.n)).join('')}</div>`), 2250, 1060)

// Storyboard GIF: every tour screen, cross-fading, about 2 s each.
const story = TOUR(T.paper)
ANIMS.push({ file: 'anim-tour-v2.gif', duration: story.length * 2.0, fps: 12, html: animDoc(
  `<div style="position:relative;width:402px;height:874px">${story.map((s, i) => `<div id="f${i}" style="position:absolute;inset:0;opacity:${i ? 0 : 1}">${s.f}</div>`).join('')}</div>`,
  `${ease} window.render=(t)=>{const n=${story.length}; for(let i=0;i<n;i++){const a=i*2.0, b=a+2.0; const v=(i?seg(t,a-.3,a):1)-(i<n-1?seg(t,b-.3,b):0); document.getElementById('f'+i).style.opacity=Math.max(0,Math.min(1,v));}}`) })

// --- First-run screens in the v1 look ------------------------------------------------------------------------
const firstRun = (t, { title, sub, button, note = '' }) => phone(t, layer(`<div style="height:64px"></div>
  <div style="position:absolute;left:28px;right:28px;top:300px;color:${t.text};text-align:center">
    <div style="font-size:30px;font-weight:800;line-height:1.25">${title}</div>
    <div style="font-size:19px;line-height:1.5;margin-top:14px;opacity:.85">${sub}</div>${note}</div>`) +
  (button ? startBtn(t, button) : ''))
const FR = (t) => [
  { n: 'Welcome', f: firstRun(t, { title: 'Seal shows what people around you are saying.', sub: 'It all happens on this phone. Setup takes about a minute.', button: 'Set up' }), cap: 'First screen. No mascot (it only lives in the launch).' },
  { n: 'Microphone', f: firstRun(t, { title: 'Seal needs the microphone.', sub: 'Tap Allow on the next screen. What it hears stays on this phone.', button: 'Continue' }), cap: 'Right before iOS asks. (The iOS question itself is drawn by iOS.)' },
  { n: 'Mic is off', f: firstRun(t, { title: 'The microphone is off.', sub: 'Captions need it. Open Settings and turn on Microphone for Seal.', button: 'Open Settings' }), cap: 'If she said no. Comes back here by itself once it\'s on.' },
  { n: "Can't run", f: firstRun(t, { title: "This phone can't run Seal.", sub: 'It needs an iPhone 12 or newer, or an iPad with an A14 chip or newer.', button: null }), cap: 'Older devices (#101). No button: there\'s nothing to do. Wording matches the store listing.' },
  { n: 'Download stopped', f: firstRun(t, { title: "The download didn't finish.", sub: 'Seal needs the internet once, for Apple\'s English speech files. Turn on Wi-Fi and try again.', button: 'Try again' }), cap: 'One screen for every download failure (no internet, stalled, other). The reason sits in the second line.' },
]
add('03-first-run.png', 'First-run screens in the v1 look',
  board('3 · First-run screens in the v1 look', 'Today: white screens with system-blue buttons and "Hi! Let\'s get you set up." Proposed: the chosen theme (Paper here, Night below), plain words, the gummy button where there is something to do, fades between screens. The launch dance still covers the speech download and warm-up.',
    `<div class="row">${FR(T.paper).map((s) => fig(s.f, s.cap, s.n)).join('')}</div><div class="row">${FR(T.night).map((s) => fig(s.f, 'Night.', s.n)).join('')}</div>`), 2250, 2100)

// --- Credits and Jump to latest ------------------------------------------------------------------------------
const credits = (t) => phone(t, layer(`<div class="topbar" style="color:${t.text}"><div style="position:absolute;left:0;font-size:17px;font-weight:700;color:${t.gear}">‹ Settings</div><span style="font-size:20px;font-weight:800">Credits</span></div>
  <div style="color:${t.text}">
    <div class="small" style="opacity:.75;margin:6px 0 10px">Seal is built on free, open work by these people.</div>
    ${[['Apple Speech', 'Speech to text, on this phone.'], ['FluidAudio', 'Telling voices apart. Apache 2.0.'], ['Sortformer (NVIDIA)', 'The voice model. CC BY 4.0.'], ['OpenDyslexic', 'Abbie Gonzalez. Bitstream Vera license.'], ['Atkinson Hyperlegible', 'Braille Institute. SIL Open Font License.']].map(([a, b]) => `<div style="padding:13px 0;border-bottom:1px solid ${t.line}"><div style="font-weight:800;font-size:17px">${a}</div><div class="small" style="opacity:.75">${b}</div></div>`).join('')}
    <div class="small" style="margin-top:16px;color:${t.gear};font-weight:700">Full license texts ›</div>
  </div>`))
const jumpA = (t) => phone(t, layer(main(t, 'Listening')) + `<div style="position:absolute;left:0;right:0;bottom:118px;z-index:30;display:grid;place-items:center">${retro(t, '↓ Latest', null, `font-size:21px;background:${t.bg};padding:6px 10px`)}</div>` + stopDot())
const jumpB = (t) => phone(t, layer(main(t, 'Listening')) + `<div style="position:absolute;left:0;right:0;bottom:118px;z-index:30;display:grid;place-items:center"><div class="btn" style="height:46px;padding:0 22px;border-radius:23px;font-size:17px;${primary(t)}">↓ Latest</div></div>` + stopDot())
const main = (t, status = 'Listening') => topbar(t, status) + captions(t)
add('04-credits-and-jump.png', 'Credits and Jump to latest',
  board('4 · Credits, and "Jump to latest"', 'Credits: same borderless style as the saved list, fading in over Settings; one thin line between entries; the full license texts one tap further. Jump to latest: shows only after she scrolls back while captions are coming in, and fades away once she\'s back at the newest line. Two styles to pick from.',
    `<div class="row">${fig(credits(T.paper), 'Credits (Paper).', '1')}${fig(credits(T.night), 'Credits (Night).', '2')}${fig(jumpA(T.paper), '<b>Jump A:</b> retro words, like [ Save ] / [ New ].', 'A')}${fig(jumpB(T.paper), '<b>Jump B:</b> a small gummy button, like Start.', 'B')}${fig(jumpA(T.night), 'Jump A on Night.', 'A, dark')}</div>`), 2250, 1060)
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
const tmp = fs.mkdtempSync('/private/tmp/claude-501/round3-frames-')
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
