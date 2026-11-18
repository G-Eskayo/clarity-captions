#!/usr/bin/env node
// Extract battery metrics from seal-feedback-*.json beta reports
// Usage: node parse-beta-report.mjs <report1.json> [report2.json ...]
// Outputs: array of { build, engine, device.model, battery.dropPercentPer30Min, battery.maxThermalState, minutes }

import fs from 'fs'

const inputFiles = process.argv.slice(2)

if (!inputFiles.length) {
  console.error('Usage: node parse-beta-report.mjs <report1.json> [report2.json ...]')
  console.error('  Reads seal-feedback-*.json files and extracts battery metrics per conversation')
  console.error('  Outputs: JSON array of { build, engine, device, battery, minutes }')
  process.exit(1)
}

const results = []

for (const filepath of inputFiles) {
  if (!fs.existsSync(filepath)) {
    console.error(`File not found: ${filepath}`)
    continue
  }

  let report
  try {
    const raw = fs.readFileSync(filepath, 'utf-8')
    report = JSON.parse(raw)
  } catch (err) {
    console.error(`Failed to parse ${filepath}: ${err.message}`)
    continue
  }

  if (!report.conversations || !Array.isArray(report.conversations)) {
    console.error(`${filepath}: no conversations array`)
    continue
  }

  for (const conv of report.conversations) {
    if (!conv.battery) {
      continue // Skip conversations without battery data
    }

    results.push({
      build: report.app?.build || conv.build || null,
      engine: conv.engine || null,
      engineFallback: conv.engineFallback || null,
      device: {
        model: report.device?.model || null,
        os: report.device?.os || null,
      },
      battery: {
        dropPercentPer30Min: conv.battery?.dropPercentPer30Min ?? null,
        maxThermalState: conv.battery?.maxThermalState || null,
      },
      minutes: conv.minutes ?? null,
      rating: conv.rating ?? null,
      speakers: conv.speakers?.detected ?? null,
      micLevel: conv.micLevel?.medianDBFS ?? null,
      lag: {
        p50: conv.lag?.p50Seconds ?? null,
        p95: conv.lag?.p95Seconds ?? null,
      },
      conversationId: conv.id || null,
      recordedBuild: conv.build || null,
      sentAt: report.sentAt || null,
    })
  }
}

// Output sorted by build, engine, device for easier grouping
results.sort((a, b) => {
  const buildCmp = (a.build ?? 0) - (b.build ?? 0)
  if (buildCmp !== 0) return buildCmp
  const engineCmp = (a.engine || '').localeCompare(b.engine || '')
  if (engineCmp !== 0) return engineCmp
  return (a.device.model || '').localeCompare(b.device.model || '')
})

console.log(JSON.stringify(results, null, 2))
