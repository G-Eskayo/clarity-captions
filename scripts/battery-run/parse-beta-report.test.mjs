// Tests for parse-beta-report.mjs: node --test scripts/battery-run/parse-beta-report.test.mjs
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { execSync } from 'child_process'
import { writeFileSync, unlinkSync, mkdtempSync } from 'fs'
import { tmpdir } from 'os'
import path from 'path'

const SCRIPT = 'scripts/battery-run/parse-beta-report.mjs'

test('parse-beta-report: extracts battery metrics from valid report', () => {
  const dir = mkdtempSync(path.join(tmpdir(), 'report-'))
  const report = path.join(dir, 'seal-feedback-11-20261114-1030.json')
  const data = {
    schema: 1,
    app: { build: '11' },
    device: { model: 'iPhone17,4', os: 'iOS 26.1' },
    conversations: [
      {
        id: 'test1',
        engine: 'parakeet-ultra-pal6',
        battery: { dropPercentPer30Min: 6.5, maxThermalState: 'fair' },
        minutes: 23.4,
        rating: 8,
      },
    ],
  }
  writeFileSync(report, JSON.stringify(data))

  try {
    const result = JSON.parse(execSync(`node ${SCRIPT} ${report}`).toString())
    assert.strictEqual(Array.isArray(result), true)
    assert.strictEqual(result.length, 1)
    assert.strictEqual(result[0].build, '11')
    assert.strictEqual(result[0].engine, 'parakeet-ultra-pal6')
    assert.strictEqual(result[0].battery.dropPercentPer30Min, 6.5)
  } finally {
    unlinkSync(report)
  }
})

test('parse-beta-report: skips conversations without battery data', () => {
  const dir = mkdtempSync(path.join(tmpdir(), 'report-'))
  const report = path.join(dir, 'seal-feedback-11-20261114-1030.json')
  const data = {
    schema: 1,
    app: { build: '11' },
    device: { model: 'iPhone17,4' },
    conversations: [
      {
        id: 'test1',
        engine: 'parakeet-ultra-pal6',
        minutes: 5,
        // No battery field
      },
      {
        id: 'test2',
        engine: 'parakeet-ultra-pal6',
        battery: { dropPercentPer30Min: 6.5, maxThermalState: 'fair' },
        minutes: 10,
      },
    ],
  }
  writeFileSync(report, JSON.stringify(data))

  try {
    const result = JSON.parse(execSync(`node ${SCRIPT} ${report}`).toString())
    assert.strictEqual(result.length, 1)
    assert.strictEqual(result[0].id || result[0].conversationId, 'test2')
  } finally {
    unlinkSync(report)
  }
})

test('parse-beta-report: handles multiple report files', () => {
  const dir = mkdtempSync(path.join(tmpdir(), 'report-'))
  const report1 = path.join(dir, 'report1.json')
  const report2 = path.join(dir, 'report2.json')

  writeFileSync(report1, JSON.stringify({
    schema: 1,
    app: { build: '11' },
    device: { model: 'iPhone17,4' },
    conversations: [
      {
        engine: 'parakeet-ultra-pal6',
        battery: { dropPercentPer30Min: 6.5, maxThermalState: 'fair' },
      },
    ],
  }))

  writeFileSync(report2, JSON.stringify({
    schema: 1,
    app: { build: '11' },
    device: { model: 'iPhone16,4' },
    conversations: [
      {
        engine: 'parakeet-ultra-pal6',
        battery: { dropPercentPer30Min: 7.2, maxThermalState: 'serious' },
      },
    ],
  }))

  try {
    const result = JSON.parse(execSync(`node ${SCRIPT} ${report1} ${report2}`).toString())
    assert.strictEqual(result.length, 2)
    assert.strictEqual(result[0].device.model, 'iPhone16,4') // Sorted by device
    assert.strictEqual(result[1].device.model, 'iPhone17,4')
  } finally {
    unlinkSync(report1)
    unlinkSync(report2)
  }
})

test('parse-beta-report: preserves lag and speaker data', () => {
  const dir = mkdtempSync(path.join(tmpdir(), 'report-'))
  const report = path.join(dir, 'seal-feedback-11-20261114-1030.json')
  const data = {
    schema: 1,
    app: { build: '11' },
    device: { model: 'iPhone17,4' },
    conversations: [
      {
        id: 'test1',
        engine: 'parakeet-ultra-pal6',
        battery: { dropPercentPer30Min: 6.5, maxThermalState: 'fair' },
        lag: { p50Seconds: 0.4, p95Seconds: 1.1 },
        speakers: { detected: 2 },
        minutes: 15,
      },
    ],
  }
  writeFileSync(report, JSON.stringify(data))

  try {
    const result = JSON.parse(execSync(`node ${SCRIPT} ${report}`).toString())
    assert.strictEqual(result[0].lag.p50, 0.4)
    assert.strictEqual(result[0].lag.p95, 1.1)
    assert.strictEqual(result[0].speakers, 2)
  } finally {
    unlinkSync(report)
  }
})

test('parse-beta-report: handles missing file gracefully', () => {
  const result = execSync(`node ${SCRIPT} /nonexistent.json 2>&1`, { encoding: 'utf-8' })
  assert.match(result, /File not found/)
})

test('parse-beta-report: outputs empty array when no matching data', () => {
  const dir = mkdtempSync(path.join(tmpdir(), 'report-'))
  const report = path.join(dir, 'seal-feedback-11-20261114-1030.json')
  writeFileSync(report, JSON.stringify({ schema: 1, conversations: [] }))

  try {
    const result = JSON.parse(execSync(`node ${SCRIPT} ${report}`).toString())
    assert.strictEqual(Array.isArray(result), true)
    assert.strictEqual(result.length, 0)
  } finally {
    unlinkSync(report)
  }
})
