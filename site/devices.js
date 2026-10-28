// Device tabs (#184): iPhone, iPad and Mac each have their own hero and "what it does"; the rest of the page is shared.
// The address follows the tab (#ipad, #mac), and a link to anything inside a device's part opens that device.
export const DEVICES = ['iphone', 'ipad', 'mac']

/** Which device a hash belongs to: a device's own name, or the device whose part holds that id. null = shared, keep. */
export function deviceFor(hash, ownerOf) {
  const id = decodeURIComponent((hash || '').replace(/^#/, ''))
  if (!id) return DEVICES[0]
  if (DEVICES.includes(id)) return id
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
  const list = document.querySelector('[data-devices]')
  const panels = [...document.querySelectorAll('[data-device]')]
  if (!list || !panels.length) return
  const buttons = [...list.querySelectorAll('[role="tab"]')]
  const ownerOf = (id) => document.getElementById(id)?.closest('[data-device]')?.dataset.device || null
  const show = (dev, { push = false, focus = false } = {}) => {
    for (const p of panels) {
      const was = p.hasAttribute('data-off'), off = p.dataset.device !== dev
      p.toggleAttribute('data-off', off)
      if (was && !off) { p.classList.remove('enter'); void p.offsetWidth; p.classList.add('enter') } // the same fade as a version
    }
    for (const b of buttons) {
      const on = b.dataset.tab === dev
      b.setAttribute('aria-selected', String(on)); b.tabIndex = on ? 0 : -1
      if (on && focus) b.focus()
    }
    if (push) history.replaceState(null, '', dev === DEVICES[0] ? location.pathname : '#' + dev)
    document.dispatchEvent(new CustomEvent('device', { detail: dev }))
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
    const dev = deviceFor(location.hash, ownerOf)
    if (dev) show(dev)
  }
  addEventListener('hashchange', fromHash)
  // Every device has its own questions: the header's Questions goes to the ones on the page you're on.
  document.querySelector('header.top a[href="#faq"]')?.addEventListener('click', (e) => {
    const faq = document.querySelector('[data-device]:not([data-off]) [data-faq]')
    if (!faq) return
    e.preventDefault()
    faq.scrollIntoView({ behavior: still ? 'auto' : 'smooth', block: 'start' })
  })
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
  const turn = (on) => {
    pad.toggleAttribute('data-turned', on)
    btn.textContent = on ? '↻ See your side' : '↻ See their side'
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
  const m = document.querySelector('[data-mac]'); if (m) mac(m)
}
