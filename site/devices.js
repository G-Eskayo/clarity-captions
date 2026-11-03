// Feature tabs (#235): Live captioning, Translation, and Calls & meetings each have their own part of the page; the
// device list, privacy and questions underneath are shared. The pills used to be devices (#184), so the old addresses
// still land: #iphone opens captions, #ipad translation, #mac calls, and the old section ids are anchors in their new homes.
// The address follows the tab (#translation, #calls), and a link to anything inside a feature's part opens that feature.
export const FEATURES = ['captions', 'translation', 'calls']
export const OLD_TABS = { iphone: 'captions', ipad: 'translation', mac: 'calls' }

/** Which feature a hash belongs to: a feature's own name, an old device tab, or the feature whose part holds that id.
 *  null = a shared part, keep the feature you're on. */
export function featureFor(hash, ownerOf) {
  const id = decodeURIComponent((hash || '').replace(/^#/, ''))
  if (!id) return FEATURES[0]
  if (FEATURES.includes(id)) return id
  if (OLD_TABS[id]) return OLD_TABS[id]
  return ownerOf(id)
}

// Split-screen translation on iPad: each side sees the whole conversation in its own language; the other side's
// words are marked as translated. side 'you' speaks English, 'them' speaks Spanish.
export const TABLE_TALK = [
  { side: 'them', en: 'How was the drive?', es: '¿Qué tal el viaje?' },
  { side: 'you', en: 'Long, but the kids slept the whole way.', es: 'Largo, pero los niños durmieron todo el camino.' },
  { side: 'them', en: 'Good. Dinner is almost ready.', es: 'Qué bien. La cena está casi lista.' },
  { side: 'you', en: 'It smells wonderful.', es: 'Huele delicioso.' }
]
/** What one half shows for one spoken line: its reader's language, and whether it is a translation. */
export function lineFor(half, line) {
  const own = half === line.side
  return { text: half === 'you' ? line.en : line.es, translated: !own }
}

export const CALL_TALK = [
  { s: 1, text: 'Can you see us? We just sat down.' },
  { s: 2, text: 'Yes! Your captions are coming through.' },
  { s: 1, text: 'Grandpa wants to say hi to everyone.' },
  { s: 2, text: 'Hi Grandpa! We miss you.' }
]

const still = typeof window === 'undefined' || matchMedia('(prefers-reduced-motion: reduce)').matches || !('IntersectionObserver' in window)

function tabs() {
  const list = document.querySelector('[data-features]')
  const panels = [...document.querySelectorAll('[data-feature]')]
  if (!list || !panels.length) return
  const buttons = [...list.querySelectorAll('[role="tab"]')]
  const ownerOf = (id) => document.getElementById(id)?.closest('[data-feature]')?.dataset.feature || null
  const show = (dev, { push = false, focus = false } = {}) => {
    for (const p of panels) {
      const was = p.hasAttribute('data-off'), off = p.dataset.feature !== dev
      p.toggleAttribute('data-off', off)
      if (was && !off) { p.classList.remove('enter'); void p.offsetWidth; p.classList.add('enter') } // the same fade as a version
    }
    for (const b of buttons) {
      const on = b.dataset.tab === dev
      b.setAttribute('aria-selected', String(on)); b.tabIndex = on ? 0 : -1
      if (on && focus) b.focus()
    }
    if (push) history.replaceState(null, '', dev === FEATURES[0] ? location.pathname : '#' + dev)
    document.dispatchEvent(new CustomEvent('feature', { detail: dev }))
  }
  list.hidden = false
  document.documentElement.classList.add('tabs-on')
  for (const b of buttons) b.addEventListener('click', () => show(b.dataset.tab, { push: true }))
  list.addEventListener('keydown', (e) => {
    const i = buttons.findIndex((b) => b.getAttribute('aria-selected') === 'true')
    const step = { ArrowRight: 1, ArrowLeft: -1 }[e.key]
    if (step) { e.preventDefault(); show(buttons[(i + step + buttons.length) % buttons.length].dataset.tab, { push: true, focus: true }) }
    if (e.key === 'Home' || e.key === 'End') { e.preventDefault(); show(buttons[e.key === 'Home' ? 0 : buttons.length - 1].dataset.tab, { push: true, focus: true }) }
  })
  const fromHash = () => {
    const id = decodeURIComponent(location.hash.slice(1))
    // A shared part (#faq) keeps the feature you're on, or the first one on a fresh load.
    const dev = featureFor(location.hash, ownerOf) || buttons.find((b) => b.getAttribute('aria-selected') === 'true')?.dataset.tab || FEATURES[0]
    show(dev)
    // An old device address (#ipad) becomes the feature's own (#translation), at the top of the page.
    if (OLD_TABS[id]) history.replaceState(null, '', dev === FEATURES[0] ? location.pathname : '#' + dev)
  }
  addEventListener('hashchange', fromHash)
  fromHash()
}

// Plays a script line by line while it is in view, once; a still page shows it all at once.
function player(root, steps, render, { every = 1700, done } = {}) {
  let i = 0, timer = null
  const step = () => {
    if (i >= steps.length) { timer = null; done?.(); return }
    render(steps[i++], true)
    timer = setTimeout(step, every)
  }
  if (still) { steps.forEach((s) => render(s, false)); i = steps.length; return }
  new IntersectionObserver(([e]) => {
    if (e.isIntersecting && !timer && i < steps.length) timer = setTimeout(step, 600)
    if (!e.isIntersecting && timer) { clearTimeout(timer); timer = null }
  }, { threshold: 0.5 }).observe(root)
}

function tablet(wrap) {
  const pad = wrap.querySelector('.tablet'), btn = wrap.querySelector('[data-flip]')
  const halves = { you: wrap.querySelector('[data-half="you"]'), them: wrap.querySelector('[data-half="them"]') }
  for (const h of Object.values(halves)) h.querySelectorAll('.t-line').forEach((l) => l.remove())
  const render = (line, animate) => {
    for (const [half, el] of Object.entries(halves)) {
      const { text, translated } = lineFor(half, line)
      const p = document.createElement('p')
      p.className = 't-line' + (translated ? ' tr' : '') + (animate ? ' new' : '')
      if (translated) p.dataset.mark = half === 'you' ? 'Translated from Spanish' : 'Traducido del inglés'
      p.textContent = text
      el.append(p)
    }
  }
  // The page holds both labels, in its own language.
  const labels = { theirs: btn.textContent, yours: btn.dataset.other || '↻ See your side' }
  const turn = (on) => {
    pad.toggleAttribute('data-turned', on)
    btn.textContent = on ? labels.yours : labels.theirs
    btn.setAttribute('aria-pressed', String(on))
  }
  btn.hidden = false
  btn.addEventListener('click', () => turn(!pad.hasAttribute('data-turned')))
  // At the end it turns once on its own, so you see what the other person reads.
  player(pad, TABLE_TALK, render, { done: () => { if (btn.getAttribute('aria-pressed') !== 'true') turn(true) } })
}

function mac(win) {
  const lines = win.querySelector('[data-pop-lines]')
  lines.replaceChildren()
  player(win, CALL_TALK, (l, animate) => {
    const p = document.createElement('p')
    p.className = `pop-line s${l.s}` + (animate ? ' new' : '')
    p.innerHTML = `<b>Speaker ${l.s}</b>`
    p.append(l.text)
    lines.append(p)
    while (lines.children.length > 3) lines.firstElementChild.remove()
  })
}

// iPhone Duo (#258), measured from Xcode's iPhone Duo simulator profile, showing the app's real screens (see
// devices.css), playing what the real Duo simulator did when unfolded by hand (2026-11-02): folded, the outer screen
// shows translated captions. It opens like a book, hinge on the left, and the inner screen comes on in landscape with
// [ Face to face ] in the top row (FaceToFace.offersSplit: big enough for two). A touch on it; the Duo turns upright,
// each half picks its language; then the split, one half turned to each person.
// Scrolling plays that in order and scrolling back plays it backwards: duoFrame turns how far through the section you
// are (0 to 1) into the fold, the landscape screen, the touch, the turn, the portrait screens and the step's words.
const clamp = (x) => Math.min(1, Math.max(0, x))
const ease = (t) => t * t * (3 - 2 * t)
export function duoFrame(p) {
  const fold = 1 - ease(clamp((p - 0.15) / 0.2)) // folded until 0.15, open flat by 0.35
  const land = ease(clamp((p - 0.35) / 0.06)) * (1 - ease(clamp((p - 0.6) / 0.06))) // landscape screen, dark while it opens
  const press = clamp(1 - Math.abs(p - 0.48) / 0.04) // a touch on Face to face
  const turn = ease(clamp((p - 0.53) / 0.12)) // then upright by 0.65
  const lit = ease(clamp((p - 0.6) / 0.06)) // the portrait screen: choosing languages, then the split
  const pickYou = p >= 0.7 ? 1 : 0, pickThem = p >= 0.76 ? 1 : 0 // English in your half, then Español in theirs
  const touchYou = clamp(1 - Math.abs(p - 0.68) / 0.025), touchThem = clamp(1 - Math.abs(p - 0.74) / 0.025)
  const split = pickThem // both halves picked: the split's conversation
  const steps = [
    1 - ease(clamp((p - 0.17) / 0.05)),
    ease(clamp((p - 0.22) / 0.05)) * (1 - ease(clamp((p - 0.55) / 0.05))),
    ease(clamp((p - 0.6) / 0.05))
  ]
  const state = fold > 0.999 ? 'folded' : fold > 0.001 ? 'opening' : turn < 0.001 ? 'open' : turn < 0.999 ? 'turning'
    : split < 1 ? 'choosing' : 'split'
  return { fold, land, press, turn, lit, pickYou, pickThem, touchYou, touchThem, split, steps, state }
}

// ── The Duo's screens, live like the site's other demos (#258) ─────────────────────────────────────────────────────
// The app's own demo scripts (DemoMode.swift): Spanish captions translated into English for the folded and landscape
// screens (the last line is still being said, so it stays as said, grey), and the ticket-counter conversation for the
// split (speaker 0 speaks Spanish in their half, speaker 1 English in yours). Timing from demo.js: 3 words every
// 350 ms, 900 ms between lines, a fade-in once per finished line.
export const DUO_CAPTIONS = [
  { s: 0, said: '¿Está encendido? Di algo para que lo veamos.', tr: 'Is it on? Say something so we can see.' },
  { s: 1, said: 'Hola. Mis palabras aparecen en la pantalla.', tr: 'Hi. My words are showing up on the screen.' },
  { s: 0, said: 'También funciona en modo avión. Nada sale del teléfono.', tr: 'It works in airplane mode too. Nothing leaves the phone.' },
  { sound: '[Laughter]' },
  { s: 1, said: '¿Y empieza una línea nueva cuando habla otra persona?', tr: 'And it starts a new line when someone else talks?' },
  { s: 0, said: 'Cuando cambia la voz, sí. Puede confundir voces que se parecen.', tr: 'When the voice changes, yes. It can mix up voices that sound alike.' },
  { s: 1, said: 'Bueno saberlo. Entonces, qué probamos primero', unfinished: true }
]
export const DUO_TALK = [
  { s: 0, said: 'Hola, buenas tardes. ¿En qué le puedo ayudar?', tr: 'Hi, good afternoon. How can I help you?' },
  { s: 1, said: 'I need the train to the airport.', tr: 'Necesito el tren al aeropuerto.' },
  { s: 0, said: 'Sale del andén cuatro, cada veinte minutos.', tr: 'It leaves from platform four, every twenty minutes.' },
  { s: 1, said: 'Do I buy the ticket here or on the train?', tr: '¿Compro el billete aquí o en el tren?' },
  { s: 0, said: 'Aquí, en la máquina. Acepta tarjeta.', tr: 'Here, at the machine. It takes cards.' },
  { s: 1, said: 'Great, thank you so much', tr: 'Genial, muchas gracias' }
]
const DUO_CHUNK_MS = 350, DUO_LINE_MS = 900, DUO_HOLD_MS = 2600
/** demo.js's chunksOf: 3 more words at a time, ending with the whole line. */
export const duoChunks = (t) => { const w = t.split(' '), o = []; for (let n = 3; n < w.length; n += 3) o.push(w.slice(0, n).join(' ')); o.push(t); return o }
const esc = (t) => t.replace(/&/g, '&amp;').replace(/</g, '&lt;')

/** One half of the split, or the one-way screen (half = null): what each finished line, and the line being said, shows. */
export function duoBlocks(script, done, partial, half = null) {
  const own = half === 'you' ? 1 : half === 'them' ? 0 : null
  const out = []
  script.slice(0, done).forEach((l, i) => {
    if (l.sound) { out.push({ sound: l.sound, i }); return }
    if (l.unfinished || (own !== null && l.s === own)) out.push({ said: l.said, own: true, s: l.s, i, vol: !!l.unfinished })
    else out.push({ tr: l.tr, said: l.said, s: l.s, i })
  })
  if (partial) out.push({ said: partial.text, vol: true, s: script[partial.i].s, i: partial.i })
  return out
}

const ICON = {
  gear: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 1 1-2.83 2.83l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 1 1-4 0v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 1 1-2.83-2.83l.06-.06A1.65 1.65 0 0 0 4.68 15a1.65 1.65 0 0 0-1.51-1H3a2 2 0 1 1 0-4h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 1 1 2.83-2.83l.06.06A1.65 1.65 0 0 0 9 4.68a1.65 1.65 0 0 0 1-1.51V3a2 2 0 1 1 4 0v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 1 1 2.83 2.83l-.06.06A1.65 1.65 0 0 0 19.4 9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 1 1 0 4h-.09a1.65 1.65 0 0 0-1.51 1z"/></svg>',
  list: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M9 6h11M9 12h11M9 18h11"/><circle cx="4.5" cy="6" r="1.2" fill="currentColor" stroke="none"/><circle cx="4.5" cy="12" r="1.2" fill="currentColor" stroke="none"/><circle cx="4.5" cy="18" r="1.2" fill="currentColor" stroke="none"/></svg>',
  stop: '<svg viewBox="0 0 20 20" fill="none" stroke="#fff" stroke-width="3.2" stroke-linecap="round"><path d="M5 5l10 10M15 5L5 15"/></svg>',
  ring: '<svg viewBox="0 0 40 40" fill="none"><circle cx="20" cy="20" r="17" stroke="#BDBDBD" stroke-width="2.5" stroke-dasharray="1 5" stroke-linecap="round"/><path d="M8 29.5A15 15 0 1 1 32 29.5" stroke="#34C759" stroke-width="3.5" stroke-linecap="round"/><path d="M13 19a10 10 0 0 1 14 0M15.6 22a6 6 0 0 1 8.8 0" stroke="#000" stroke-width="2.4" stroke-linecap="round"/><circle cx="20" cy="25.5" r="1.8" fill="#000"/><path d="M20.5 6l-2 4h3l-2 4" stroke="#000" stroke-width="1.2"/></svg>',
  mark: '<svg viewBox="0 0 26 20"><rect x="1" y="1" width="14" height="12" rx="3" fill="currentColor"/><text x="8" y="10.5" font-size="9" font-weight="700" text-anchor="middle" fill="#FAF5E6" font-family="system-ui,sans-serif">A</text><rect x="10.5" y="6.5" width="14" height="12" rx="3" fill="#FAF5E6" stroke="currentColor" stroke-width="1.6"/><text x="17.5" y="16" font-size="8.5" font-weight="700" text-anchor="middle" fill="currentColor" font-family="system-ui,sans-serif">文</text></svg>'
}
const at = (x, y, extra = '') => `style="inset-inline-start:${x}px;top:${y}px;${extra}"`
const icon = (name, x, y) => `<span class="dx-icon" ${at(x, y)}>${ICON[name]}</span>`
const statusBar = (x, y, ringX, ringY) => `<span class="dx-time" ${at(x, y)}>9:41</span><span class="dx-ring" ${at(ringX, ringY)}>${ICON.ring}</span>`
const stopButton = (x, y) => `<span class="dx-stop" ${at(x, y)}>${ICON.stop}</span>`
const homeBar = (x, y, w) => `<span class="dx-home" ${at(x, y, `width:${w}px`)}></span>`
const capsBox = (x, y, w, h) => `<div class="dx-caps" data-caps ${at(x, y, `width:${w}px;height:${h}px`)}></div>`

const DUO_SCREENS = {
  outer: () => icon('gear', 25, 25) + `<span class="dx-status" ${at(0, 29, 'width:380px')}>Listening</span>` + icon('list', 321, 25) +
    statusBar(388, 84, 398, 108) + capsBox(16, 64, 334, 455) + stopButton(309, 569) + homeBar(150, 662, 166),
  land: () => icon('gear', 25, 25) + `<span class="dx-status" ${at(0, 29, 'width:866px')}>Listening</span>` +
    `<span class="dx-f2f" ${at(615, 30)}>[ Face to face ]</span>` + icon('list', 816, 25) +
    statusBar(872, 30, 882, 56) + capsBox(16, 70, 820, 470) + stopButton(794, 560) + homeBar(353, 653, 245),
  port: () => {
    // With the line centred, the two halves are the same size, so their lists mirror each other exactly.
    const half = (who, lang, first = 120) => `<div class="dx-half ${who}" data-half="${who}">` +
      `<span class="dx-label1" data-when="list">Tap your language to start</span><span class="dx-label1" data-when="picked">Listening</span>` +
      `<span class="dx-label2" data-when="picked">${lang}</span>` +
      ['English', 'Español', 'Français'].map((l, i) => `<span class="dx-pick" data-when="list" ${at(0, first + i * 64)}>[ ${l} ]</span>`).join('') +
      `<div class="dx-caps" data-caps data-when="picked"></div>` + (who === 'you' ? stopButton(597, 359) : '') + '</div>'
    return half('them', 'Español') + '<span class="dx-mid"></span>' + half('you', 'English') +
      statusBar(540, 39, 600, 27) + homeBar(215, 937, 238) +
      `<span class="dx-touch you" ${at(334, 610)}></span><span class="dx-touch them" ${at(334, 277)}></span>`
  }
}

function blockHTML(b, labels, fresh) {
  const cls = b.i === fresh ? ' dx-new' : ''
  if (b.sound) return `<p class="dx-sound${cls}">${esc(b.sound)}</p>`
  const spk = labels ? `<b class="dx-spk s${b.s}">Speaker ${b.s + 1}</b>` : ''
  if (b.tr) return `<div class="${cls.trim()}">${spk}<p class="dx-tx"><i class="dx-mark">${ICON.mark}</i>${esc(b.tr)}</p><p class="dx-said">${esc(b.said)}</p></div>`
  return `<div class="${b.vol ? '' : cls.trim()}">${spk}<p class="${b.vol ? 'dx-vol' : 'dx-own'}">${esc(b.said)}</p></div>`
}

// A script played a few words at a time, like the app; it loops while the Duo is in view.
function duoPlayer(script, render, { from = 0 } = {}) {
  let done = from, partial = null, fresh = -1, timer = null, on = false
  const draw = () => { render(done, partial, fresh); fresh = -1 } // a finished line fades in once, not on every redraw
  const next = () => {
    if (!on) return
    if (done >= script.length) { timer = setTimeout(() => { done = 0; partial = null; fresh = -1; draw(); timer = setTimeout(next, DUO_LINE_MS) }, DUO_HOLD_MS); return }
    const l = script[done]
    if (l.sound) { fresh = done; done++; partial = null; draw(); timer = setTimeout(next, DUO_LINE_MS); return }
    const chunks = duoChunks(l.said)
    let k = 0
    const word = () => {
      if (!on) return
      if (k < chunks.length) { partial = { i: done, text: chunks[k++] }; draw(); timer = setTimeout(word, DUO_CHUNK_MS); return }
      if (l.unfinished) { timer = setTimeout(() => { partial = null; done++; draw(); next() }, DUO_LINE_MS); return }
      partial = null; fresh = done; done++; draw(); timer = setTimeout(next, DUO_LINE_MS)
    }
    word()
  }
  return {
    start() { if (on) return; on = true; draw(); timer = setTimeout(next, 400) },
    stop() { on = false; clearTimeout(timer) },
    reset() { this.stop(); done = from; partial = null; fresh = -1; draw() },
    get running() { return on }
  }
}

function duoScreens(stage) {
  const screens = (name) => [...stage.querySelectorAll(`[data-dx="${name}"]`)]
  for (const name of Object.keys(DUO_SCREENS)) for (const el of screens(name)) el.innerHTML = DUO_SCREENS[name]()
  const oneWay = [...screens('outer'), ...screens('land')].map((el) => el.querySelector('[data-caps]'))
  const halves = (who) => screens('port').map((el) => el.querySelector(`[data-half="${who}"] [data-caps]`))
  const captions = duoPlayer(DUO_CAPTIONS, (done, partial, fresh) => {
    const html = duoBlocks(DUO_CAPTIONS, done, partial).map((b) => blockHTML(b, true, fresh)).join('')
    for (const c of oneWay) c.innerHTML = html
  }, { from: 3 })
  const talk = duoPlayer(DUO_TALK, (done, partial, fresh) => {
    for (const who of ['you', 'them']) {
      const html = duoBlocks(DUO_TALK, done, partial, who).map((b) => blockHTML(b, false, fresh)).join('')
      for (const c of halves(who)) c.innerHTML = html
    }
  })
  captions.reset(); talk.reset()
  return {
    picked(you, them) {
      for (const el of screens('port')) {
        el.querySelector('[data-half="you"]').toggleAttribute('data-picked', !!you)
        el.querySelector('[data-half="them"]').toggleAttribute('data-picked', !!them)
      }
    },
    play(visible, split) {
      if (visible) captions.start(); else captions.stop()
      if (visible && split) talk.start(); else if (!split) talk.reset(); else talk.stop()
    }
  }
}

function duoScroll(section) {
  if (still) return // Reduce Motion or no observers: the two still pictures stay
  const track = section.querySelector('.duo-track'), stage = section.querySelector('[data-duo-stage]')
  const steps = [...section.querySelectorAll('.duo-steps li')]
  stage.hidden = false
  section.querySelector('[data-duo-stills]').hidden = true
  section.classList.add('is-scrolling')
  const live = duoScreens(stage)
  let k = 0
  const measure = () => { // points to px; measured again when the tab shows or the window changes
    const w = stage.getBoundingClientRect().width / 979
    if (w && w !== k) { k = w; stage.style.setProperty('--k', w.toFixed(5)) }
  }
  let visible = false, split = false
  new IntersectionObserver(([e]) => { visible = e.isIntersecting; live.play(visible, split) }).observe(stage)
  let queued = false
  const update = () => {
    queued = false
    const r = track.getBoundingClientRect(), range = r.height - innerHeight
    measure()
    const f = duoFrame(range > 0 ? clamp(-r.top / range) : 0)
    stage.style.setProperty('--f', f.fold.toFixed(4))
    stage.style.setProperty('--lo', f.fold > 0.97 ? '0' : '1') // folded flat, the inside is hidden under the outside
    stage.style.setProperty('--whole', f.fold === 0 ? '1' : '0') // flat open: one whole screen, no line at the hinge
    stage.style.setProperty('--split', f.split.toFixed(4))
    stage.style.setProperty('--press', f.press.toFixed(4))
    stage.style.setProperty('--r', f.turn.toFixed(4))
    stage.style.setProperty('--lit', f.lit.toFixed(4))
    stage.style.setProperty('--land', f.land.toFixed(4))
    stage.style.setProperty('--pb', f.touchYou.toFixed(4))
    stage.style.setProperty('--pt', f.touchThem.toFixed(4))
    live.picked(f.pickYou, f.pickThem)
    if (!!f.split !== split) { split = !!f.split; live.play(visible, split) }
    stage.dataset.state = f.state
    steps.forEach((li, i) => li.style.setProperty('--o', f.steps[i].toFixed(3)))
  }
  const queue = () => { if (!queued) { queued = true; requestAnimationFrame(update) } }
  addEventListener('scroll', queue, { passive: true })
  addEventListener('resize', queue)
  document.addEventListener('feature', queue)
  update()
}

// A picture that draws itself once it comes into view (bars grow, the iPad grows to scale, lines arrive).
function grow(el) {
  if (still) { el.classList.add('in'); return }
  el.querySelectorAll('li').forEach((li, i) => li.style.setProperty('--i', i))
  const io = new IntersectionObserver(([e]) => { if (e.isIntersecting) { el.classList.add('in'); io.disconnect() } }, { threshold: 0.35 })
  io.observe(el)
}

// A call rings, it is captioned, it ends: the three pictures light in turn while they're in view.
function story(list) {
  const items = [...list.children]
  if (still) { items.forEach((li) => li.classList.add('on')); return }
  let i = 0, timer = null
  const light = () => { items.forEach((li, k) => li.classList.toggle('on', k === i)); i = (i + 1) % items.length }
  new IntersectionObserver(([e]) => {
    if (e.isIntersecting && !timer) { light(); timer = setInterval(light, 2200) }
    if (!e.isIntersecting && timer) { clearInterval(timer); timer = null }
  }, { threshold: 0.5 }).observe(list)
}

if (typeof document !== 'undefined') {
  tabs()
  document.querySelectorAll('[data-grow]').forEach(grow)
  const s = document.querySelector('[data-story]'); if (s) story(s)
  const t = document.querySelector('[data-tablet]'); if (t) tablet(t)
  const d = document.querySelector('[data-duo]'); if (d) duoScroll(d)
  const m = document.querySelector('[data-mac]'); if (m) mac(m)
}
