// The website's working demo of Seal Speak (#44, brought up to v1.0 in #142): Start, captions arriving a few words at
// a time, a new line when the voice changes, sound labels, ✕ to pause with [ Save ] / [ New ] on a dim, [ Save ] →
// [ ✔ ] → [ Saved ] with the brackets easing, tap the dim to read, hold on empty space to bring it back, hold words to
// copy, the list icon for saved conversations with [ Share ] over [ Delete ], and Settings (preview, colors, size,
// lettering, stop when it's quiet, the tour, About). Everything moves with fades only, like the app.
// Ported from the app's DemoMode (3 words every 350 ms as a still-changing caption, then final; 900 ms between
// lines) and FluidTiming. Nothing plays on its own; with reduced motion the conversation appears at once.
import { THEMES, LETTERING, SIZES, BASE_PX, SCRIPT, IDLE_STOP, SAVED_EXAMPLE } from './seal-data.js'

const CHUNK = 3
const CHUNK_MS = 350
const LINE_MS = 900
const QUIET_MS = 4000
const HOLD_MS = 500
// FluidTiming.swift: [ ✔ ] holds 0.7 s; the brackets ease over 0.4 s; the word goes out, then in, as they land.
const SAVE_CHECK_HOLD = 0.7
const MORPH = { full: 0.4, reduced: 0.2 }
const WORD_SWAP = { full: [0.16, 0.16, 0.26], reduced: [0.08, 0.08, 0.12] }

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

// A saved conversation as plain text, the way the app copies and shares it (TranscriptExport.swift): "Speaker 1: …".
export function transcriptOf(lines) {
  return lines.map((l) => (l.sound ? `[${l.sound}]` : `Speaker ${l.speaker + 1}: ${l.text}`)).join('\n')
}

// The muted second line of a saved row (SavedDates.preview): flattened, cut at 70 characters with an ellipsis.
export function previewOf(lines) {
  const flat = transcriptOf(lines).replace(/\n/g, ' ').trim()
  return flat.length > 70 ? flat.slice(0, 70).trim() + '…' : flat
}

// How a saved conversation is named (SavedDates.title): "Today, 8:56 AM", "Yesterday, 7:12 PM", then dates.
export function savedTitle(date, now = new Date()) {
  const time = date.toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit' })
  const day = (d) => new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime()
  const diff = Math.round((day(now) - day(date)) / 86400000)
  if (diff === 0) return `Today, ${time}`
  if (diff === 1) return `Yesterday, ${time}`
  return `${date.toLocaleDateString('en-US', { month: 'short', day: 'numeric' })}, ${time}`
}

export function init(root, { reducedMotion = false, storage = null, now = () => new Date() } = {}) {
  const $ = (sel) => root.querySelector(sel)
  const captions = $('[data-captions]')
  const live = $('[data-live]')
  const status = $('[data-status]')
  const statusSub = $('[data-status-sub]')
  const start = $('[data-start]')
  const stop = $('[data-stop]')
  const veil = $('[data-veil]')
  const veilWords = $('[data-veil-words]')
  const newQ = $('[data-new-q]')
  const save = $('[data-save]')
  const fresh = $('[data-new]')
  const gear = $('[data-gear]')
  const list = $('[data-list]')
  const panel = $('[data-settings]')
  const done = $('[data-done]')
  const savedPage = $('[data-saved-list]')
  const rows = $('[data-saved-rows]')
  const search = $('[data-saved-search]')
  const onePage = $('[data-saved-one]')
  const oneTitle = $('[data-one-title]')
  const oneText = $('[data-one-text]')
  const oneVeil = $('[data-one-veil]')
  const oneWords = $('[data-one-words]')
  const delQ = $('[data-del-q]')
  const copyBtn = $('[data-copy]')
  const hint = $('[data-hint]')
  const tour = $('[data-tour]')
  const tourNote = $('[data-tour-note]')

  const prefs = load(storage)
  const T = reducedMotion ? 'reduced' : 'full'
  let state = 'idle' // idle | running | paused
  let veilOn = true
  let step = 0
  let partial = null
  let timers = []
  let saved = false
  let page = 'captions' // captions | settings | saved | one
  let openId = null
  let selText = ''
  let hintTimer = null
  const hintsShown = new Set()
  const yesterday = new Date(now().getTime() - 86400000)
  yesterday.setHours(19, 12, 0, 0)
  const savedList = [{ id: 1, at: yesterday, lines: SAVED_EXAMPLE }]
  let nextId = 2

  function load(s) {
    const fallback = { theme: 'paper', lettering: 'opendyslexic', size: 2, quiet: 0 }
    try {
      const p = JSON.parse(s?.getItem('seal.demo') || '{}')
      return {
        theme: THEMES.some((t) => t.id === p.theme) ? p.theme : fallback.theme,
        lettering: LETTERING.some((l) => l.id === p.lettering) ? p.lettering : fallback.lettering,
        size: Number.isInteger(p.size) && p.size >= 0 && p.size < SIZES.length ? p.size : fallback.size,
        quiet: Number.isInteger(p.quiet) && p.quiet >= 0 && p.quiet < IDLE_STOP.length ? p.quiet : fallback.quiet
      }
    } catch {
      return fallback
    }
  }
  function persist() {
    try { storage?.setItem('seal.demo', JSON.stringify(prefs)) } catch { /* not remembered, still works */ }
  }

  // Fades only: an element is either on or off (data-off), and CSS fades opacity between the two.
  const fade = (el, on) => { if (on) el.removeAttribute('data-off'); else el.setAttribute('data-off', '') }
  const isOn = (el) => !el.hasAttribute('data-off')

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
    for (const b of root.querySelectorAll('[data-quiet]')) b.setAttribute('aria-pressed', String(Number(b.dataset.quiet) === prefs.quiet))
    $('[data-smaller]').disabled = prefs.size === 0
    $('[data-bigger]').disabled = prefs.size === SIZES.length - 1
  }

  // Caption lines drawn the same way live and in a saved conversation: a speaker label when the voice changes.
  function drawLines(into, blocks) {
    into.replaceChildren()
    let prev = null
    for (const b of blocks) {
      const div = document.createElement('div')
      div.className = 'd-line'
      const words = document.createElement('span')
      if (b.sound) {
        div.classList.add('d-sound')
        words.textContent = `[${b.sound}]`
        prev = null
      } else {
        if (b.speaker !== prev) {
          const label = document.createElement('div')
          label.className = `d-spk d-s${b.speaker + 1}`
          label.textContent = `Speaker ${b.speaker + 1}`
          div.append(label)
        }
        words.textContent = b.text
        if (b.final === false) words.className = 'd-vol'
        prev = b.speaker
      }
      div.append(words)
      into.append(div)
    }
  }

  function render() {
    const blocks = blocksFor(SCRIPT, step, partial)
    drawLines(captions, blocks)
    if (!blocks.length) {
      const empty = document.createElement('p')
      empty.className = 'd-empty'
      empty.textContent = state === 'idle' ? 'Captions show up here.' : ''
      captions.append(empty)
    }
    captions.scrollTop = captions.scrollHeight
    root.dataset.state = state
    status.textContent = state === 'paused' ? 'Paused' : state === 'running' ? 'Listening' : 'Ready'
    fade(start, state !== 'running')
    fade(stop, state === 'running')
    fade(veil, state === 'paused' && veilOn)
    captions.tabIndex = state === 'paused' && !veilOn ? 0 : -1
    tour.disabled = state === 'running'
    tourNote.textContent = state === 'running' ? 'Pause captions first, then come back here.' : ''
  }

  function announce(b) {
    // Only finished lines go to screen readers, so they aren't read three words at a time.
    live.textContent = b.sound ? `[${b.sound}]` : `Speaker ${b.speaker + 1}: ${b.text}`
  }

  function showHint(text, key = null, ms = 3200) {
    if (key) { if (hintsShown.has(key)) return; hintsShown.add(key) }
    clearTimeout(hintTimer)
    hint.textContent = text
    fade(hint, true)
    hintTimer = setTimeout(() => fade(hint, false), ms)
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
    askNew(false)
    render()
    playFrom(step)
  }
  function pause() {
    clearTimers()
    partial = null
    state = 'paused'
    veilOn = true
    statusSub.hidden = true
    render()
    save.focus()
  }

  // [ word ] buttons: when the word changes, the brackets ease to the new width while the old word fades out and the
  // new one fades in (RetroWordsText in the app). The word box's width is what animates.
  function setWord(btn, word, animate = true) {
    const box = btn.querySelector('.rw')
    const txt = box.querySelector('.rw-t')
    if (!animate || typeof box.getBoundingClientRect !== 'function') { txt.textContent = word; box.style.width = ''; return }
    const [out, inDelay, inDur] = WORD_SWAP[T]
    const from = box.getBoundingClientRect().width
    const probe = txt.cloneNode()
    probe.textContent = word
    probe.className = 'rw-probe'
    box.append(probe)
    const to = probe.getBoundingClientRect().width
    probe.remove()
    box.style.transition = 'none'
    box.style.width = `${from}px`
    void box.offsetWidth
    box.style.transition = `width ${MORPH[T]}s ease-in-out`
    box.style.width = `${to}px`
    txt.style.transition = `opacity ${out}s ease-out`
    txt.style.opacity = '0'
    setTimeout(() => {
      txt.textContent = word
      txt.style.transition = `opacity ${inDur}s ease-in`
      txt.style.opacity = '1'
    }, (out + inDelay) * 1000)
  }

  function resetSave() {
    setWord(save, 'Save', false)
    save.classList.remove('d-saved')
    save.removeAttribute('aria-disabled')
    save.setAttribute('aria-label', 'Save conversation')
  }
  function doSave() {
    if (saved || state !== 'paused') return
    saved = true
    save.setAttribute('aria-disabled', 'true')
    save.classList.add('d-saved')
    save.setAttribute('aria-label', 'Saved')
    setWord(save, '✔')
    setTimeout(() => { setWord(save, 'Saved'); save.setAttribute('aria-label', 'Conversation saved') }, (reducedMotion ? 0.3 : SAVE_CHECK_HOLD) * 1000)
    const lines = blocksFor(SCRIPT, step).filter((b) => b.sound || b.text).map((b) => (b.sound ? { sound: b.sound } : { speaker: b.speaker, text: b.text }))
    savedList.unshift({ id: nextId++, at: now(), lines })
    drawSaved()
  }

  // [ New ] on an unsaved conversation asks first, in place: "Start a new conversation? This one isn't saved."
  function askNew(on) {
    fade(newQ, on)
    fade(veilWords, !on)
  }
  function requestNew() {
    if (!saved && step > 0) { askNew(true); $('[data-new-no]').focus(); return }
    doNew()
  }
  function doNew() {
    clearTimers()
    askNew(false)
    state = 'idle'
    step = 0
    partial = null
    saved = false
    resetSave()
    render()
    start.focus()
  }

  // The dim: one tap clears it to read, scroll and copy; a hold on empty space (or Enter / Escape) brings it back.
  function clearVeil() {
    if (isOn(newQ)) { askNew(false); return }
    veilOn = false
    render()
    captions.focus()
    showHint('Hold on empty space to bring back Save and New', 'veil')
  }
  function bringBackVeil() {
    if (state !== 'paused' || veilOn) return
    window.getSelection?.()?.removeAllRanges()
    veilOn = true
    render()
    save.focus()
  }

  const emptySpot = (target, area) => target === area || target.classList?.contains('d-line') || target.classList?.contains('d-empty')
  function onHoldEmpty(area, fn) {
    let t = null
    let x0 = 0
    let y0 = 0
    const cancel = () => { if (t) { clearTimeout(t); t = null } }
    area.addEventListener('pointerdown', (e) => {
      if (!emptySpot(e.target, area)) return
      x0 = e.clientX
      y0 = e.clientY
      cancel()
      t = setTimeout(() => { t = null; fn() }, HOLD_MS)
    })
    area.addEventListener('pointermove', (e) => { if (Math.hypot(e.clientX - x0, e.clientY - y0) > 10) cancel() })
    for (const ev of ['pointerup', 'pointercancel', 'pointerleave']) area.addEventListener(ev, cancel)
  }

  // Pages fade over the captions on the same background: Settings, Saved, one saved conversation.
  function go(next) {
    page = next
    fade(panel, next === 'settings')
    fade(savedPage, next === 'saved')
    fade(onePage, next === 'one')
    gear.setAttribute('aria-expanded', String(next === 'settings'))
    clearTimeout(hintTimer)
    fade(hint, false)
    window.getSelection?.()?.removeAllRanges()
    if (next === 'settings') done.focus()
    else if (next === 'saved') { drawSaved(); $('[data-saved-back]').focus() }
    else if (next === 'one') $('[data-one-back]').focus()
  }

  function drawSaved() {
    const q = (search.value || '').trim().toLowerCase()
    const shown = savedList.filter((c) => !q || transcriptOf(c.lines).toLowerCase().includes(q))
    rows.replaceChildren()
    $('[data-saved-empty]').hidden = savedList.length > 0
    search.parentElement.hidden = savedList.length === 0
    for (const c of shown) {
      const b = document.createElement('button')
      b.className = 'd-row'
      b.dataset.row = String(c.id)
      const title = document.createElement('strong')
      title.textContent = savedTitle(c.at, now())
      const prev = document.createElement('span')
      prev.textContent = previewOf(c.lines)
      b.append(title, prev)
      b.addEventListener('click', () => openSaved(c.id))
      rows.append(b)
    }
  }

  function openSaved(id) {
    const c = savedList.find((x) => x.id === id)
    if (!c) return
    openId = id
    oneTitle.textContent = savedTitle(c.at, now())
    drawLines(oneText, c.lines)
    askDelete(false)
    fade(oneVeil, true)
    go('one')
  }
  function askDelete(on) {
    fade(delQ, on)
    fade(oneWords, !on)
  }
  function clearOneVeil() {
    if (isOn(delQ)) { askDelete(false); return }
    fade(oneVeil, false)
    oneText.tabIndex = 0
    oneText.focus()
    showHint('Hold words to copy. Hold empty space to bring back Share and Delete.', 'one', 4200)
  }
  function bringBackOneVeil() {
    if (isOn(oneVeil)) return
    window.getSelection?.()?.removeAllRanges()
    oneText.tabIndex = -1
    fade(oneVeil, true)
    $('[data-share]').focus()
  }

  // Hold words to select them (the browser's own selection here), and [ Copy ] fades in.
  function onSelection() {
    const sel = window.getSelection?.()
    const node = sel && !sel.isCollapsed ? sel.anchorNode : null
    const inside = node && (captions.contains(node) || oneText.contains(node))
    selText = inside ? sel.toString().trim() : ''
    fade(copyBtn, Boolean(selText))
  }
  function doCopy() {
    const text = selText
    if (!text) return
    try { navigator.clipboard?.writeText(text)?.catch?.(() => {}) } catch { /* copying isn't allowed here; the demo carries on */ }
    window.getSelection?.()?.removeAllRanges()
    fade(copyBtn, false)
    showHint('Copied', null, 1400)
  }

  start.addEventListener('click', startCaptions)
  stop.addEventListener('click', pause)
  save.addEventListener('click', doSave)
  fresh.addEventListener('click', requestNew)
  $('[data-new-yes]').addEventListener('click', doNew)
  $('[data-new-no]').addEventListener('click', () => { askNew(false); fresh.focus() })
  veil.addEventListener('click', (e) => { if (e.target === veil || e.target === veilWords || e.target === newQ) clearVeil() })
  $('[data-veil-read]').addEventListener('click', clearVeil)
  onHoldEmpty(captions, bringBackVeil)
  captions.addEventListener('keydown', (e) => { if (e.key === 'Enter' || e.key === 'Escape') bringBackVeil() })

  gear.addEventListener('click', () => go(page === 'settings' ? 'captions' : 'settings'))
  done.addEventListener('click', () => { go('captions'); gear.focus() })
  panel.addEventListener('keydown', (e) => { if (e.key === 'Escape') done.click() })
  list.addEventListener('click', () => go('saved'))
  $('[data-saved-back]').addEventListener('click', () => { go('captions'); list.focus() })
  savedPage.addEventListener('keydown', (e) => { if (e.key === 'Escape') $('[data-saved-back]').click() })
  search.addEventListener('input', drawSaved)
  $('[data-one-back]').addEventListener('click', () => go('saved'))
  onePage.addEventListener('keydown', (e) => {
    if (e.key === 'Escape') { if (isOn(oneVeil)) go('saved'); else bringBackOneVeil() }
  })
  oneVeil.addEventListener('click', (e) => { if (e.target === oneVeil || e.target === oneWords || e.target === delQ) clearOneVeil() })
  $('[data-one-read]').addEventListener('click', clearOneVeil)
  onHoldEmpty(oneText, bringBackOneVeil)
  $('[data-share]').addEventListener('click', () => showHint('On your iPhone, this opens the share sheet: Notes, Messages, Mail, Files or AirDrop.', null, 4200))
  $('[data-delete]').addEventListener('click', () => { askDelete(true); $('[data-del-no]').focus() })
  $('[data-del-no]').addEventListener('click', () => { askDelete(false); $('[data-delete]').focus() })
  $('[data-del-yes]').addEventListener('click', () => {
    const i = savedList.findIndex((c) => c.id === openId)
    if (i >= 0) savedList.splice(i, 1)
    go('saved')
  })

  copyBtn.addEventListener('pointerdown', (e) => e.preventDefault())
  copyBtn.addEventListener('click', doCopy)
  document.addEventListener('selectionchange', onSelection)

  for (const b of root.querySelectorAll('[data-theme]')) b.addEventListener('click', () => { prefs.theme = b.dataset.theme; persist(); applyLook() })
  for (const b of root.querySelectorAll('[data-lettering]')) b.addEventListener('click', () => { prefs.lettering = b.dataset.lettering; persist(); applyLook() })
  for (const b of root.querySelectorAll('[data-quiet]')) b.addEventListener('click', () => { prefs.quiet = Number(b.dataset.quiet); persist(); applyLook() })
  $('[data-smaller]').addEventListener('click', () => { prefs.size = Math.max(0, prefs.size - 1); persist(); applyLook() })
  $('[data-bigger]').addEventListener('click', () => { prefs.size = Math.min(SIZES.length - 1, prefs.size + 1); persist(); applyLook() })
  tour.addEventListener('click', () => showHint('In the app, this replays the short how-to tour on the captions.', null, 3600))

  applyLook()
  resetSave()
  render()
  drawSaved()
  root.dataset.ready = '1'
  // Fades switch on after the first paint (see .phone[data-ready="2"] in index.html), so nothing fades in on load.
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
