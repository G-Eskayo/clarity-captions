// The website's working demo of Seal Speak (#44): Start, captions arriving a few words at a time, a new line when the
// voice changes, sound labels, ✕ to pause with [ Save ] / [ New ], and Settings for colours, lettering and size.
// Ported from the app's DemoMode (3 words every 350 ms as a still-changing caption, then final; 900 ms between
// lines). Nothing plays on its own; with reduced motion the conversation appears at once.
import { THEMES, LETTERING, SIZES, BASE_PX, SCRIPT } from './seal-data.js'

const CHUNK = 3
const CHUNK_MS = 350
const LINE_MS = 900
const QUIET_MS = 4000

export function chunksOf(text, size = CHUNK) {
  const words = text.split(' ')
  const out = []
  for (let n = size; n < words.length; n += size) out.push(words.slice(0, n).join(' '))
  out.push(text)
  return out
}

// What the caption area shows after `step` steps of the script, with the step in progress at `partial` words.
export function blocksFor(steps, upTo, partial = null) {
  const blocks = []
  for (let i = 0; i < upTo && i < steps.length; i++) {
    const s = steps[i]
    const final = !(s.unfinished && i === steps.length - 1)
    blocks.push(s.sound ? { sound: s.sound } : { speaker: s.speaker, text: s.text, final })
  }
  if (partial && upTo < steps.length && !steps[upTo].sound) blocks.push({ speaker: steps[upTo].speaker, text: partial, final: false })
  return blocks
}

export function init(root, { reducedMotion = false, storage = null } = {}) {
  const $ = (sel) => root.querySelector(sel)
  const captions = $('[data-captions]')
  const live = $('[data-live]')
  const status = $('[data-status]')
  const statusSub = $('[data-status-sub]')
  const start = $('[data-start]')
  const stop = $('[data-stop]')
  const veil = $('[data-veil]')
  const save = $('[data-save]')
  const fresh = $('[data-new]')
  const gear = $('[data-gear]')
  const panel = $('[data-settings]')
  const done = $('[data-done]')

  const prefs = load(storage)
  let state = 'idle' // idle | running | paused
  let step = 0
  let partial = null
  let timers = []
  let saved = false

  function load(s) {
    try {
      const p = JSON.parse(s?.getItem('seal.demo') || '{}')
      return { theme: THEMES.some((t) => t.id === p.theme) ? p.theme : 'paper', lettering: LETTERING.some((l) => l.id === p.lettering) ? p.lettering : 'opendyslexic', size: Number.isInteger(p.size) && p.size >= 0 && p.size < SIZES.length ? p.size : 2 }
    } catch {
      return { theme: 'paper', lettering: 'opendyslexic', size: 2 }
    }
  }
  function persist() {
    try { storage?.setItem('seal.demo', JSON.stringify(prefs)) } catch { /* not remembered, still works */ }
  }

  function applyLook() {
    const t = THEMES.find((x) => x.id === prefs.theme)
    const l = LETTERING.find((x) => x.id === prefs.lettering)
    const s = root.style
    s.setProperty('--d-bg', t.bg)
    s.setProperty('--d-text', t.text)
    s.setProperty('--d-gear', t.gear)
    s.setProperty('--d-s1', t.speakers[0])
    s.setProperty('--d-s2', t.speakers[1])
    s.setProperty('--d-saved', t.saved)
    s.setProperty('--d-lip', lip(t.text))
    s.setProperty('--d-font', l.css)
    s.setProperty('--d-size', `${(BASE_PX * SIZES[prefs.size]).toFixed(1)}px`)
    root.dataset.dark = t.dark ? '1' : '0'
    for (const b of root.querySelectorAll('[data-theme]')) b.setAttribute('aria-pressed', String(b.dataset.theme === prefs.theme))
    for (const b of root.querySelectorAll('[data-lettering]')) b.setAttribute('aria-pressed', String(b.dataset.lettering === prefs.lettering))
    $('[data-smaller]').disabled = prefs.size === 0
    $('[data-bigger]').disabled = prefs.size === SIZES.length - 1
  }

  function render() {
    const blocks = blocksFor(SCRIPT, step, partial)
    captions.replaceChildren()
    let prev = null
    for (const b of blocks) {
      const div = document.createElement('div')
      div.className = 'd-line'
      if (b.sound) {
        div.classList.add('d-sound')
        div.textContent = `[${b.sound}]`
        prev = null
      } else {
        if (b.speaker !== prev) {
          const label = document.createElement('div')
          label.className = `d-spk d-s${b.speaker + 1}`
          label.textContent = `Speaker ${b.speaker + 1}`
          div.append(label)
        }
        const words = document.createElement('span')
        words.textContent = b.text
        if (!b.final) words.className = 'd-vol'
        div.append(words)
        prev = b.speaker
      }
      captions.append(div)
    }
    if (!blocks.length) {
      const hint = document.createElement('p')
      hint.className = 'd-empty'
      hint.textContent = state === 'idle' ? 'Captions show up here.' : ''
      captions.append(hint)
    }
    captions.scrollTop = captions.scrollHeight
    root.dataset.state = state
    status.textContent = state === 'paused' ? 'Paused' : 'Listening'
    start.hidden = state === 'running'
    stop.hidden = state !== 'running'
    veil.hidden = state !== 'paused'
    start.textContent = state === 'paused' ? 'Start again' : 'Start captions'
  }

  function announce(b) {
    // Only finished lines go to screen readers, so they aren't read three words at a time.
    live.textContent = b.sound ? `[${b.sound}]` : `Speaker ${b.speaker + 1}: ${b.text}`
  }

  function clearTimers() {
    timers.forEach(clearTimeout)
    timers = []
  }
  const later = (ms, fn) => timers.push(setTimeout(fn, ms))

  function playFrom(i) {
    if (i >= SCRIPT.length) {
      later(QUIET_MS, () => { if (state === 'running') statusSub.hidden = false })
      return
    }
    const s = SCRIPT[i]
    if (s.sound || reducedMotion) {
      step = i + 1
      partial = null
      render()
      if (!s.unfinished) announce(s)
      return reducedMotion ? playFrom(i + 1) : later(LINE_MS, () => playFrom(i + 1))
    }
    const parts = chunksOf(s.text)
    parts.forEach((p, n) => later(n * CHUNK_MS, () => {
      const last = n === parts.length - 1
      if (last) {
        step = i + 1
        partial = null
        if (!s.unfinished) announce(s)
      } else partial = p
      render()
      if (last) later(LINE_MS, () => playFrom(i + 1))
    }))
  }

  function startCaptions() {
    if (state === 'running') return
    if (state === 'idle' || step >= SCRIPT.length) { step = 0; partial = null; saved = false; resetSave() }
    state = 'running'
    statusSub.hidden = true
    render()
    playFrom(step)
  }
  function pause() {
    clearTimers()
    partial = null
    state = 'paused'
    statusSub.hidden = true
    render()
    save.focus()
  }
  function resetSave() {
    save.textContent = '[ Save ]'
    save.classList.remove('d-saved')
    save.disabled = false
  }
  function doSave() {
    if (saved) return
    saved = true
    save.disabled = true
    save.classList.add('d-saved')
    save.textContent = '[ ✔ ]'
    later(reducedMotion ? 0 : 600, () => { save.textContent = '[ Saved ]' })
  }
  function doNew() {
    clearTimers()
    state = 'idle'
    step = 0
    partial = null
    saved = false
    resetSave()
    render()
    start.focus()
  }

  start.addEventListener('click', startCaptions)
  stop.addEventListener('click', pause)
  save.addEventListener('click', doSave)
  fresh.addEventListener('click', doNew)
  gear.addEventListener('click', () => { panel.hidden = false; gear.setAttribute('aria-expanded', 'true'); done.focus() })
  done.addEventListener('click', () => { panel.hidden = true; gear.setAttribute('aria-expanded', 'false'); gear.focus() })
  panel.addEventListener('keydown', (e) => { if (e.key === 'Escape') done.click() })
  for (const b of root.querySelectorAll('[data-theme]')) b.addEventListener('click', () => { prefs.theme = b.dataset.theme; persist(); applyLook() })
  for (const b of root.querySelectorAll('[data-lettering]')) b.addEventListener('click', () => { prefs.lettering = b.dataset.lettering; persist(); applyLook() })
  $('[data-smaller]').addEventListener('click', () => { prefs.size = Math.max(0, prefs.size - 1); persist(); applyLook() })
  $('[data-bigger]').addEventListener('click', () => { prefs.size = Math.min(SIZES.length - 1, prefs.size + 1); persist(); applyLook() })

  applyLook()
  render()
  root.dataset.ready = '1'
  // Fades for theme changes switch on after the first paint (see .phone[data-ready="2"] in index.html).
  requestAnimationFrame?.(() => requestAnimationFrame(() => { root.dataset.ready = '2' }))
  return { startCaptions, pause, doSave, doNew, get state() { return state }, get step() { return step } }
}

// The gummy button's lip (build.mjs lipColor): 28% lighter for a dark fill, 28% darker for a light one.
export function lip(hex) {
  const [r, g, b] = [1, 3, 5].map((i) => parseInt(hex.slice(i, i + 2), 16))
  const lum = (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255
  const f = (v) => Math.round(lum < 0.25 ? v + (255 - v) * 0.28 : v * 0.72)
  return `#${[r, g, b].map((v) => f(v).toString(16).padStart(2, '0')).join('')}`
}

if (typeof document !== 'undefined') {
  const root = document.querySelector('[data-demo]')
  let storage = null
  try { storage = window.localStorage } catch { storage = null }
  if (root) init(root, { reducedMotion: window.matchMedia?.('(prefers-reduced-motion: reduce)').matches, storage })
}
