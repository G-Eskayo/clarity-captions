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
  const lit = ease(clamp((p - 0.6) / 0.06)) // the portrait screens: choosing languages, then the split
  const split = ease(clamp((p - 0.76) / 0.12)) // the split by 0.88
  const steps = [
    1 - ease(clamp((p - 0.17) / 0.05)),
    ease(clamp((p - 0.22) / 0.05)) * (1 - ease(clamp((p - 0.55) / 0.05))),
    ease(clamp((p - 0.6) / 0.05))
  ]
  const state = fold > 0.999 ? 'folded' : fold > 0.001 ? 'opening' : turn < 0.001 ? 'open' : turn < 0.999 ? 'turning'
    : split < 0.001 ? 'choosing' : split < 0.999 ? 'splitting' : 'split'
  return { fold, land, press, turn, lit, split, steps, state }
}

function duoScroll(section) {
  if (still) return // Reduce Motion or no observers: the two still pictures stay
  const track = section.querySelector('.duo-track'), stage = section.querySelector('[data-duo-stage]')
  const steps = [...section.querySelectorAll('.duo-steps li')]
  stage.hidden = false
  section.querySelector('[data-duo-stills]').hidden = true
  section.classList.add('is-scrolling')
  let queued = false
  const update = () => {
    queued = false
    const r = track.getBoundingClientRect(), range = r.height - innerHeight
    const f = duoFrame(range > 0 ? clamp(-r.top / range) : 0)
    stage.style.setProperty('--f', f.fold.toFixed(4))
    stage.style.setProperty('--lo', f.fold > 0.97 ? '0' : '1') // folded flat, the inside is hidden under the outside
    stage.style.setProperty('--split', f.split.toFixed(4))
    stage.style.setProperty('--press', f.press.toFixed(4))
    stage.style.setProperty('--r', f.turn.toFixed(4))
    stage.style.setProperty('--lit', f.lit.toFixed(4))
    stage.style.setProperty('--land', f.land.toFixed(4))
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
