#!/usr/bin/env node
// Parse an xctrace export (CSV from Energy Log / Core ML trace) and emit component breakdown
// Usage: node parse-trace.mjs <export.csv>
// Outputs JSON: { thermal, battery, componentSplit: { screen, mic, parakeet, sortformer, soundLabel } }

import fs from 'fs'
import path from 'path'

const [, , inputPath] = process.argv

if (!inputPath) {
  console.error('Usage: node parse-trace.mjs <xctrace-export.csv>')
  console.error('  Reads xctrace export from Instruments Energy Log / Core ML trace')
  console.error('  Outputs JSON with battery drop, max thermal, and component breakdown')
  process.exit(1)
}

if (!fs.existsSync(inputPath)) {
  console.error(`File not found: ${inputPath}`)
  process.exit(1)
}

const csv = fs.readFileSync(inputPath, 'utf-8')
const lines = csv.trim().split('\n')

if (lines.length < 2) {
  console.error('CSV has no data rows')
  process.exit(1)
}

// Parse CSV header and data; xctrace export structure varies, but typically has:
// columns for Time, Process, Category, Event, and measurements like CPU%, Neural%, Thermal, Battery%
const header = lines[0].split(',').map(h => h.trim())
const findColumn = name => header.findIndex(h => h.toLowerCase().includes(name.toLowerCase()))

const timeIdx = findColumn('time')
const thermalIdx = findColumn('thermal')
const batteryIdx = findColumn('battery')
const neuralIdx = findColumn('neural')

const data = lines.slice(1).map(line => {
  const cols = line.split(',').map(c => c.trim())
  return {
    time: timeIdx >= 0 ? cols[timeIdx] : null,
    thermal: thermalIdx >= 0 ? parseFloat(cols[thermalIdx]) || null : null,
    battery: batteryIdx >= 0 ? parseFloat(cols[batteryIdx]) || null : null,
    neural: neuralIdx >= 0 ? parseFloat(cols[neuralIdx]) || null : null,
    raw: cols,
  }
})

// Extract battery drop, max thermal, and rough component split
// Note: xctrace's component labeling is app/process specific; this is a placeholder
// In practice, run Instruments' Core ML template and export the profiling data

const batteryStart = data[0]?.battery ?? null
const batteryEnd = data[data.length - 1]?.battery ?? null
const batteryDrop = batteryStart && batteryEnd ? batteryStart - batteryEnd : null

const thermals = data.filter(d => d.thermal !== null).map(d => d.thermal)
const maxThermal = thermals.length ? Math.max(...thermals) : null
const thermalState = maxThermal ? (maxThermal > 80 ? 'critical' : maxThermal > 60 ? 'serious' : 'fair') : null

// Component split (placeholder; real data from Core ML profile)
// In the actual trace, identify processes/threads by name:
// - "Sortformer" or "diarizer" threads
// - "Parakeet" or "ASR" threads
// - "SoundLabel" or "classifier" threads
// and sum their Neural Engine %, CPU %, or sample counts
const componentSplit = {
  parakeetEncoderDecoder: null, // Neural Engine % spent in encoder+decoder
  sortformerDiarizer: null,      // Neural Engine % spent in diarizer
  soundLabeler: null,            // Neural Engine % spent in sound classification
  notes: 'Component breakdown requires Core ML template export with process/thread breakdown. Run "xcrun xctrace export --input <trace.ctrace> --tpl "Core ML" --output summary.txt" and parse thread timings.',
}

const result = {
  dataPoints: data.length,
  batteryDropPercent: batteryDrop,
  batteryDropPerHour: batteryDrop && data.length ? (batteryDrop * 60) / (data.length / 60) : null,
  maxThermalStatePercent: maxThermal,
  maxThermalStateLabel: thermalState,
  componentSplit,
  rawData: {
    first: data[0],
    last: data[data.length - 1],
    count: data.length,
  },
}

console.log(JSON.stringify(result, null, 2))
