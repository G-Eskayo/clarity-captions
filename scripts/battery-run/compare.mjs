#!/usr/bin/env node
// Compare xctrace lab result with seal-feedback beta reports: few-point rule and validity checks
// Usage: node compare.mjs --trace <export.csv> --reports <report1.json> [report2.json ...] --engine <engine> [--manifest <manifest.json>]
// Validates: battery drop within ±2%, thermal state match, device model code, validity rules

import fs from 'fs'
import path from 'path'

const args = process.argv.slice(2)
const findArg = (name, defaultVal) => {
  const idx = args.indexOf(name)
  return idx >= 0 && idx + 1 < args.length ? args[idx + 1] : defaultVal
}

const traceFile = findArg('--trace', null)
const manifestFile = findArg('--manifest', null)
const engine = findArg('--engine', null)
const reportFiles = args.filter((_, i, a) => a[i - 1] === '--reports').map((_, i, a) => a[i])
  || args.filter(arg => arg.endsWith('.json') && arg !== traceFile && arg !== manifestFile)

if (!traceFile || !reportFiles.length || !engine) {
  console.error('Usage: node compare.mjs --trace <export.csv> --reports <report1.json> [...] --engine <engine> [--manifest <manifest.json>]')
  console.error('  Validates lab (Instruments) vs. field (beta reports) agreement')
  console.error('  Tests: device model, build, battery ±2%, thermal state, validity rules')
  process.exit(1)
}

// Load and parse files
let labBattery = null
let labThermal = null
let manifest = null

if (fs.existsSync(traceFile)) {
  // Parse trace (simplified; real parsing via xctrace export template)
  const csv = fs.readFileSync(traceFile, 'utf-8')
  const lines = csv.trim().split('\n')
  if (lines.length >= 2) {
    // Placeholder: in practice, use xctrace's Core ML template and parse process timings
    // For now, extract first/last battery and max thermal from the CSV
    const rows = lines.slice(1).map(l => {
      const [time, battery, thermal] = l.split(',').slice(0, 3).map(s => s.trim())
      return { battery: parseFloat(battery), thermal: parseFloat(thermal) }
    })
    const batteries = rows.map(r => r.battery).filter(b => b !== null && !Number.isNaN(b))
    const thermals = rows.map(r => r.thermal).filter(t => t !== null && !Number.isNaN(t))
    if (batteries.length >= 2) {
      labBattery = batteries[0] - batteries[batteries.length - 1]
    }
    if (thermals.length) {
      labThermal = Math.max(...thermals)
    }
  }
}

if (manifestFile && fs.existsSync(manifestFile)) {
  try {
    manifest = JSON.parse(fs.readFileSync(manifestFile, 'utf-8'))
  } catch (err) {
    console.error(`Failed to parse manifest: ${err.message}`)
  }
}

// Load beta reports and extract matching engine/build data
const reports = []
for (const file of reportFiles) {
  if (!fs.existsSync(file)) continue
  try {
    const data = JSON.parse(fs.readFileSync(file, 'utf-8'))
    if (!data.conversations) continue
    for (const conv of data.conversations) {
      if (conv.engine !== engine) continue
      reports.push({
        build: data.app?.build || conv.build,
        device: data.device?.model,
        battery: conv.battery?.dropPercentPer30Min,
        thermal: conv.battery?.maxThermalState,
        minutes: conv.minutes,
        file,
        convId: conv.id,
      })
    }
  } catch (err) {
    console.error(`Failed to parse ${file}: ${err.message}`)
  }
}

// Validation tests
const tests = {
  test1_labDataExists: labBattery !== null && labThermal !== null,
  test2_fieldDataExists: reports.length > 0,
  test3_manifestFieldsFilled: manifest && manifest.runs && manifest.runs[0] && manifest.runs[0].endChargePercent !== null,
  test4_buildMatch: manifest && reports.every(r => r.build === parseInt(manifest.runs[0].build)),
  test5_deviceMatch: manifest && reports.every(r => r.device === manifest.runs[0].model),
  test6_batteryAgreement: reports.length && labBattery !== null && reports.length > 0
    && reports.every(r => r.battery && Math.abs(r.battery - (labBattery * 2)) <= 2), // scale lab to 30min
  test7_thermalAgreement: reports.every(r => r.thermal === (labThermal > 60 ? 'serious' : 'fair')),
  test8_validityRules: reports.every(r => {
    // Validity: no negative battery, no missing critical fields, no extreme outliers
    return r.battery >= 0 && r.battery <= 25 && r.thermal && r.minutes > 0
  }),
}

const results = {
  engine,
  labData: {
    batteryDropPercent: labBattery,
    maxThermalStatePercent: labThermal,
  },
  fieldData: {
    conversationCount: reports.length,
    batteryMedian: reports.length ? reports.map(r => r.battery).sort((a, b) => a - b)[Math.floor(reports.length / 2)] : null,
    thermalStates: [...new Set(reports.map(r => r.thermal))],
  },
  tests,
  passed: Object.values(tests).every(t => t === true || t === undefined),
  reportSummary: reports.slice(0, 3), // First 3 for inspection
}

console.log(JSON.stringify(results, null, 2))
