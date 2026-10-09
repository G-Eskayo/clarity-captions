// Renders the launch prototype's round-3 frame strips and GIF clips into design/mascot/frames/v3/.
// Usage: node design/mascot/capture_frames.mjs [path-to-playwright-core] [chromium-executable]
// Every frame comes from launch-prototype.html's own render(t), so the evidence is exactly what the page plays.
// (Earlier rounds' frames were rendered by earlier versions of the page: round 1 in frames/ (commit 6d7917e),
// round 2 in frames/v2/ (commit 7d71cb2).)
import { execFileSync } from 'node:child_process'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'

const here = import.meta.dirname
const pw = process.argv[2] || path.join(os.homedir(), '.agents/dashboard/node_modules/playwright-core/index.mjs')
const executablePath = process.argv[3] || undefined
const { chromium } = await import(pw)

const base = { entrance: 'pop', ripple: 'faces', launch: 'ordinary', speed: 'fast', theme: 'light', motion: 'full' }
const runs = [
  // Both entrances, with tiny seal faces riding the ripple.
  { name: 'pop-faces-light' },
  { name: 'pop-faces-dark', theme: 'dark' },
  { name: 'slide-faces-light', entrance: 'slide' },
  { name: 'slide-faces-dark', entrance: 'slide', theme: 'dark' },
  // The other ripples, with the pop-up entrance.
  { name: 'pop-bubbles-light', ripple: 'bubbles' },
  { name: 'pop-bubbles-dark', ripple: 'bubbles', theme: 'dark' },
  { name: 'pop-rings-light', ripple: 'rings' },
  { name: 'pop-rings-dark', ripple: 'rings', theme: 'dark' },
  // A slow first launch: setup outlasts the dance, so the bar shows.
  { name: 'first-launch-slow-light', launch: 'first', speed: 'slow' },
  { name: 'first-launch-slow-dark', launch: 'first', speed: 'slow', theme: 'dark' },
].map((r) => ({ ...base, ...r }))

const outDir = path.join(here, 'frames', 'v3')
fs.mkdirSync(outDir, { recursive: true })

const browser = await chromium.launch(executablePath ? { executablePath } : {})
const page = await browser.newPage({ viewport: { width: 402, height: 874 } })
await page.goto('file://' + path.join(here, 'launch-prototype.html') + '?chrome=0&t=0')

for (const run of runs) {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'seal-'))
  const tl = await page.evaluate((r) => { const { name, ...s } = r; Object.assign(window.proto.state, s); return window.proto.timeline() }, run)
  // Strip: 8 moments from start to the main screen, always including the ready beat and the hand-off.
  const strip = [0.2 * tl.dance, 0.5 * tl.dance, 0.85 * tl.dance, tl.beatStart + tl.beat * 0.35,
    tl.handoffStart + 0.3, tl.handoffStart + 0.75, tl.handoffStart + 1.05, tl.handoffStart + 1.4]
  for (const [i, t] of strip.entries()) {
    await page.evaluate((t) => window.proto.render(t), t)
    await page.screenshot({ path: path.join(tmp, `s${i}.png`) })
  }
  execFileSync('ffmpeg', ['-y', '-loglevel', 'error', '-i', path.join(tmp, 's%d.png'),
    '-vf', 'scale=180:-1,tile=8x1:padding=6:color=white', '-frames:v', '1', path.join(outDir, `${run.name}-strip.png`)])
  // Clip: 20 fps GIF, 240 px wide, holding the main screen for 0.6 s at the end.
  const fps = 20
  const n = Math.ceil((tl.end + 0.6) * fps)
  for (let i = 0; i < n; i++) {
    await page.evaluate((t) => window.proto.render(t), i / fps)
    await page.screenshot({ path: path.join(tmp, `f${i}.png`) })
  }
  execFileSync('ffmpeg', ['-y', '-loglevel', 'error', '-framerate', String(fps), '-i', path.join(tmp, 'f%d.png'),
    '-vf', 'scale=240:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=64[p];[b][p]paletteuse', '-loop', '0',
    path.join(outDir, `${run.name}.gif`)])
  fs.rmSync(tmp, { recursive: true, force: true })
  console.log(run.name.padEnd(30), `ready ${tl.ready.toFixed(2)} s · beat ${tl.beatStart.toFixed(2)} s · hand-off ${tl.handoffStart.toFixed(2)} s · end ${tl.end.toFixed(2)} s`)
}
await browser.close()
