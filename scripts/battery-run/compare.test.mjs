// Tests for compare.mjs: node --test scripts/battery-run/compare.test.mjs
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { execSync } from 'child_process'
import { writeFileSync, unlinkSync, mkdtempSync } from 'fs'
import { tmpdir } from 'os'
import path from 'path'

const SCRIPT = 'scripts/battery-run/compare.mjs'

test('compare: validates agreement between lab and field data', () => {
  const dir = mkdtempSync(path.join(tmpdir(), 'compare-'))

  // Create a trace CSV (lab data)
  const trace = path.join(dir, 'trace.csv')
  writeFileSync(trace, 'Time,Battery %,Thermal %\n0,100,35\n3600,87,45\n')

  // Create a manifest
  const manifest = path.join(dir, 'manifest.json')
  writeFileSync(manifest, JSON.stringify({
    runs: [{
      device: 'iPhone 17',
      model: 'iPhone17,4',
      build: 11,
      engine: 'parakeet-ultra-pal6',
      startChargePercent: 100,
      endChargePercent: 87,
    }],
  }))

  // Create a beta report (field data, matching build/engine)
  const report = path.join(dir, 'report.json')
  writeFileSync(report, JSON.stringify({
    schema: 1,
    app: { build: '11' },
    device: { model: 'iPhone17,4' },
    conversations: [
      {
        engine: 'parakeet-ultra-pal6',
        battery: { dropPercentPer30Min: 6.5, maxThermalState: 'fair' },
        minutes: 20,
      },
      {
        engine: 'parakeet-ultra-pal6',
        battery: { dropPercentPer30Min: 6.8, maxThermalState: 'fair' },
        minutes: 25,
      },
    ],
  }))

  try {
    const result = JSON.parse(
      execSync(`node ${SCRIPT} --trace ${trace} --reports ${report} --engine parakeet-ultra-pal6 --manifest ${manifest}`).toString()
    )

    // Check structure
    assert.ok(result.engine)
    assert.ok(result.labData)
    assert.ok(result.fieldData)
    assert.ok(result.tests)

    // Check that data was extracted
    assert.strictEqual(typeof result.labData.batteryDropPercent, 'number')
    assert.strictEqual(typeof result.fieldData.conversationCount, 'number')
  } finally {
    unlinkSync(trace)
    unlinkSync(manifest)
    unlinkSync(report)
  }
})

test('compare: counts matching conversations by engine', () => {
  const dir = mkdtempSync(path.join(tmpdir(), 'compare-'))

  const trace = path.join(dir, 'trace.csv')
  writeFileSync(trace, 'Time,Battery %,Thermal %\n0,100,35\n3600,87,45\n')

  const report = path.join(dir, 'report.json')
  writeFileSync(report, JSON.stringify({
    schema: 1,
    app: { build: '11' },
    device: { model: 'iPhone17,4' },
    conversations: [
      {
        engine: 'parakeet-ultra-pal6',
        battery: { dropPercentPer30Min: 6.5, maxThermalState: 'fair' },
      },
      {
        engine: 'apple-speechanalyzer',  // Different engine, should not match
        battery: { dropPercentPer30Min: 8.0, maxThermalState: 'fair' },
      },
    ],
  }))

  try {
    const result = JSON.parse(
      execSync(`node ${SCRIPT} --trace ${trace} --reports ${report} --engine parakeet-ultra-pal6`).toString()
    )
    assert.strictEqual(result.fieldData.conversationCount, 1) // Only Parakeet
  } finally {
    unlinkSync(trace)
    unlinkSync(report)
  }
})

test('compare: requires --trace, --reports, --engine arguments', () => {
  const result = execSync(`node ${SCRIPT} 2>&1`, { encoding: 'utf-8' })
  assert.match(result, /Usage:/)
})

test('compare: outputs JSON with test results', () => {
  const dir = mkdtempSync(path.join(tmpdir(), 'compare-'))

  const trace = path.join(dir, 'trace.csv')
  writeFileSync(trace, 'Time,Battery %,Thermal %\n0,100,35\n')

  const report = path.join(dir, 'report.json')
  writeFileSync(report, JSON.stringify({
    schema: 1,
    conversations: [{
      engine: 'parakeet-ultra-pal6',
      battery: { dropPercentPer30Min: 6.5, maxThermalState: 'fair' },
    }],
  }))

  try {
    const result = JSON.parse(
      execSync(`node ${SCRIPT} --trace ${trace} --reports ${report} --engine parakeet-ultra-pal6`).toString()
    )

    // Verify test structure
    assert.ok(result.tests.test1_labDataExists !== undefined)
    assert.ok(result.tests.test2_fieldDataExists !== undefined)
    assert.ok(result.tests.test3_manifestFieldsFilled !== undefined)
    assert.ok(result.tests.test4_buildMatch !== undefined)
    assert.ok(result.tests.test5_deviceMatch !== undefined)
    assert.ok(result.tests.test6_batteryAgreement !== undefined)
    assert.ok(result.tests.test7_thermalAgreement !== undefined)
    assert.ok(result.tests.test8_validityRules !== undefined)
    assert.ok(result.passed !== undefined)
  } finally {
    unlinkSync(trace)
    unlinkSync(report)
  }
})
