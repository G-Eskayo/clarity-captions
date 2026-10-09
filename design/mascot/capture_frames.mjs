// Renders the launch prototype's frame strips and GIF clips into design/mascot/frames/.
// Usage: node design/mascot/capture_frames.mjs [path-to-playwright-core] [chromium-executable]
// Every frame comes from launch-prototype.html's own render(t), so the evidence is exactly what the page plays.
import { execFileSync } from 'node:child_process'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'

const here = import.meta.dirname
const pw = process.argv[2] || path.join(os.homedir(), '.agents/dashboard/node_modules/playwright-core/index.mjs')
const executablePath = process.argv[3] || undefined
const { chromium } = await import(pw)

const runs = [
  { name: 'A-clap-wiggle', opt: 'A', speed: 'fast', handoff: 'glide' },
  { name: 'B-balance-bubble', opt: 'B', speed: 'fast', handoff: 'glide' },
  { name: 'C-belly-slide-wave', opt: 'C', speed: 'fast', handoff: 'glide' },
  { name: 'C-slow-start-dive', opt: 'C', speed: 'slow', handoff: 'dive' },
  { name: 'A-dark', opt: 'A', speed: 'fast', handoff: 'glide', theme: 'dark' },
]
const outDir = path.join(here, 'frames')
fs.mkdirSync(outDir, { recursive: true })

const browser = await chromium.launch(executablePath ? { executablePath } : {})
const page = await browser.newPage({ viewport: { width: 390, height: 844 } })
await page.goto('file://' + path.join(here, 'launch-prototype.html') + '?chrome=0&t=0')

for (const run of runs) {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'seal-'))
  const end = await page.evaluate(r => {
    Object.assign(window.proto.state, { theme: 'light', motion: 'full' }, r)
    return window.proto.timeline().end
  }, run)
  // Strip: 8 moments from start to the start screen.
  const stripTimes = Array.from({ length: 8 }, (_, i) => (end * i) / 7)
  for (const [i, t] of stripTimes.entries()) {
    await page.evaluate(t => window.proto.render(t), t)
    await page.screenshot({ path: path.join(tmp, `s${i}.png`) })
  }
  execFileSync('ffmpeg', ['-y', '-loglevel', 'error', '-i', path.join(tmp, 's%d.png'),
    '-vf', 'scale=180:-1,tile=8x1:padding=6:color=white', '-frames:v', '1', path.join(outDir, `${run.name}-strip.png`)])
  // Clip: 20 fps GIF, 240 px wide.
  const fps = 20
  const n = Math.ceil(end * fps) + 8
  for (let i = 0; i < n; i++) {
    await page.evaluate(t => window.proto.render(t), i / fps)
    await page.screenshot({ path: path.join(tmp, `f${i}.png`) })
  }
  execFileSync('ffmpeg', ['-y', '-loglevel', 'error', '-framerate', String(fps), '-i', path.join(tmp, 'f%d.png'),
    '-vf', 'scale=240:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=64[p];[b][p]paletteuse', '-loop', '0',
    path.join(outDir, `${run.name}.gif`)])
  fs.rmSync(tmp, { recursive: true, force: true })
  console.log(run.name, `end ${end.toFixed(2)} s`, stripTimes.map(t => t.toFixed(2)).join(' '))
}
await browser.close()
