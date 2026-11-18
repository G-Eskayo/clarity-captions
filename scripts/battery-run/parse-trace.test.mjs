// Tests for parse-trace.mjs: node --test scripts/battery-run/parse-trace.test.mjs
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { execSync } from 'child_process'
import { writeFileSync, unlinkSync, mkdtempSync } from 'fs'
import { tmpdir } from 'os'
import path from 'path'

const SCRIPT = 'scripts/battery-run/parse-trace.mjs'

test('parse-trace: parses valid CSV and extracts battery drop', () => {
  const dir = mkdtempSync(path.join(tmpdir(), 'trace-'))
  const csv = path.join(dir, 'trace.csv')
  writeFileSync(csv, 'Time,Battery %,Thermal %\n0,100,25\n3600,85,35\n')

  try {
    const result = JSON.parse(execSync(`node ${SCRIPT} ${csv}`).toString())
    assert.strictEqual(typeof result.batteryDropPercent, 'number')
    assert.strictEqual(result.batteryDropPercent, 15)
    assert.strictEqual(result.dataPoints, 2) // Two data rows (excluding header)
  } finally {
    unlinkSync(csv)
  }
})

test('parse-trace: handles missing file', () => {
  const result = execSync(`node ${SCRIPT} /nonexistent.csv 2>&1`, { encoding: 'utf-8' })
  assert.match(result, /File not found/)
})

test('parse-trace: handles empty CSV', () => {
  const dir = mkdtempSync(path.join(tmpdir(), 'trace-'))
  const csv = path.join(dir, 'trace.csv')
  writeFileSync(csv, '')

  try {
    const result = execSync(`node ${SCRIPT} ${csv} 2>&1`, { encoding: 'utf-8' })
    assert.match(result, /no data rows/)
  } finally {
    unlinkSync(csv)
  }
})

test('parse-trace: maps thermal % to state label', () => {
  const dir = mkdtempSync(path.join(tmpdir(), 'trace-'))
  const csv = path.join(dir, 'trace.csv')

  // Test critical (>80%)
  writeFileSync(csv, 'Time,Battery %,Thermal %\n0,100,85\n3600,90,90\n')
  let result = JSON.parse(execSync(`node ${SCRIPT} ${csv}`).toString())
  assert.strictEqual(result.maxThermalStateLabel, 'critical')

  // Test serious (>60%)
  writeFileSync(csv, 'Time,Battery %,Thermal %\n0,100,25\n3600,85,70\n')
  result = JSON.parse(execSync(`node ${SCRIPT} ${csv}`).toString())
  assert.strictEqual(result.maxThermalStateLabel, 'serious')

  // Test fair (≤60%)
  writeFileSync(csv, 'Time,Battery %,Thermal %\n0,100,25\n3600,85,50\n')
  result = JSON.parse(execSync(`node ${SCRIPT} ${csv}`).toString())
  assert.strictEqual(result.maxThermalStateLabel, 'fair')

  unlinkSync(csv)
})

test('parse-trace: outputs JSON with required fields', () => {
  const dir = mkdtempSync(path.join(tmpdir(), 'trace-'))
  const csv = path.join(dir, 'trace.csv')
  writeFileSync(csv, 'Time,Battery %,Thermal %\n0,100,25\n')

  try {
    const result = JSON.parse(execSync(`node ${SCRIPT} ${csv}`).toString())
    assert.ok(result.batteryDropPercent !== undefined)
    assert.ok(result.maxThermalStatePercent !== undefined)
    assert.ok(result.componentSplit)
    assert.ok(result.rawData)
  } finally {
    unlinkSync(csv)
  }
})
