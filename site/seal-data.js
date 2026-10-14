// Seal Speak's six themes (Packages/CaptionCore/Sources/CaptionCore/CaptionStyle.swift) and the demo conversation for
// the website (#44). Shared by the page (demo.js) and its checks (scripts/check-site.mjs), so the colours tested for
// contrast are the colours shown.

export const THEMES = [
  { id: 'paper', name: 'Paper', dark: false, bg: '#FAF5E6', text: '#141419', gear: '#14514B', speakers: ['#14514B', '#7A350C'], saved: '#12512F' },
  { id: 'seaglass', name: 'Sea glass', dark: false, bg: '#DCEFEA', text: '#0D2F2C', gear: '#0B4842', speakers: ['#0B4842', '#6E2E0A'], saved: '#12512F' },
  { id: 'peach', name: 'Peach', dark: false, bg: '#FBE8D2', text: '#2B1A10', gear: '#6E2E0A', speakers: ['#0B4842', '#6E2E0A'], saved: '#12512F' },
  { id: 'charcoal', name: 'Charcoal', dark: true, bg: '#2B2D31', text: '#ECE6D9', gear: '#E2D9C6', speakers: ['#93DCD1', '#F2C994'], saved: '#9BE3B4' },
  { id: 'night', name: 'Night', dark: true, bg: '#1D2536', text: '#E9E3D5', gear: '#C9D6F2', speakers: ['#93DCD1', '#F2C994'], saved: '#9BE3B4' },
  { id: 'harbor', name: 'Harbor', dark: true, bg: '#173331', text: '#ECE4D3', gear: '#F2DDB5', speakers: ['#A3E3D9', '#F2C994'], saved: '#A6E8BC' }
]

export const LETTERING = [
  { id: 'opendyslexic', name: 'OpenDyslexic', css: "'OpenDyslexic', system-ui, sans-serif" },
  { id: 'atkinson', name: 'Atkinson Hyperlegible', css: "'Atkinson Hyperlegible', system-ui, sans-serif" },
  { id: 'standard', name: 'Standard', css: "-apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif" }
]

// The app's five text-size steps (CaptionStyle.swift), on a 22px base like the mock-ups.
export const SIZES = [0.75, 0.875, 1, 1.15, 1.35]
export const BASE_PX = 22

// What the demo "hears". Honest by construction (docs/design/honest-claims-2026-10-10.md): voices get Speaker 1 and
// Speaker 2, no names, no promise about who is talking. The last line stays unfinished, like a live caption.
export const SCRIPT = [
  { speaker: 0, text: 'Is it on? Say something so we can see.' },
  { speaker: 1, text: 'Hi. My words are showing up on the screen.' },
  { speaker: 0, text: 'It works in airplane mode too. Nothing leaves the phone.' },
  { sound: 'Laughter' },
  { speaker: 1, text: 'And it starts a new line when someone else talks?' },
  { speaker: 0, text: 'When the voice changes, yes. It can mix up voices that sound alike.' },
  { speaker: 1, text: 'Good to know. So what should we try first', unfinished: true }
]
