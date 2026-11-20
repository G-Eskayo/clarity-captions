// Tests for the app's price rule (check-site.mjs section 10, #228, #231): node --test scripts/app-prices.test.mjs
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { appPriceProblems, FAKE_STORE_IOS, MOCKUP_MAC, IOS_FAKE_STORE_FILE, MAC_MOCKUP_FILE } from './app-prices.mjs'

const PRICES = { app: '4.99', translationIOS: '4.99', translationMac: '1.99' }
const IOS_OK = '        if DemoMode.fakeStore { price = "$4.99"; purchase.entitlementChanged(owned: true); return }'
const MAC_OK = '    static let mockupPrice = "$1.99"'
// The two sanctioned files, each with its one allowed line; every test changes one thing.
const base = () => ({
  [IOS_FAKE_STORE_FILE]: `struct A {\n${IOS_OK}\n}`,
  [MAC_MOCKUP_FILE]: `enum DemoMode {\n${MAC_OK}\n}`,
  'Mac/Sources/TranslationMockup.swift': 'language.translationPrice = DemoMode.mockupPrice',
})

test('the sanctioned lines pass', () => {
  assert.deepEqual(appPriceProblems(base(), PRICES), [])
})

test('the sanctioned lines are built from PRICES', () => {
  assert.equal(FAKE_STORE_IOS(PRICES), 'price = "$4.99"')
  assert.equal(MOCKUP_MAC(PRICES), 'static let mockupPrice = "$1.99"')
})

test('a stray Mac price in the mock-up fails, with its file and line', () => {
  const files = { ...base(), 'Mac/Sources/TranslationMockup.swift': 'x\n        language.translationPrice = "$1.99"' }
  assert.deepEqual(appPriceProblems(files, PRICES), ['Apps/Mac/Sources/TranslationMockup.swift:2 hard-codes a price; show StoreKit\'s displayPrice'])
})

test('the Mac mock-up constant is allowed only in its own file', () => {
  const files = { ...base(), 'Spike/Sources/Other.swift': MAC_OK }
  assert.equal(appPriceProblems(files, PRICES).length, 1)
})

test('the Mac mock-up constant must carry the Mac price, not the iOS one', () => {
  const files = { ...base(), [MAC_MOCKUP_FILE]: '    static let mockupPrice = "$4.99"' }
  const p = appPriceProblems(files, PRICES)
  assert.ok(p.some((m) => m.includes('must be static let mockupPrice = "$1.99"')), p.join('\n'))
  assert.ok(p.some((m) => m.includes(':1 hard-codes a price')), p.join('\n'))
})

test('a second price in the Mac shim still fails', () => {
  const files = { ...base(), [MAC_MOCKUP_FILE]: `${MAC_OK}\n    static let other = "$1.99"` }
  assert.deepEqual(appPriceProblems(files, PRICES), [`Apps/${MAC_MOCKUP_FILE}:2 hard-codes a price; show StoreKit's displayPrice`])
})

test('the constant with something else hidden on its line fails', () => {
  const files = { ...base(), [MAC_MOCKUP_FILE]: `${MAC_OK}; let y = "$9.99"` }
  assert.equal(appPriceProblems(files, PRICES).length, 2)
})

test('a missing Mac constant is reported', () => {
  const files = { ...base(), [MAC_MOCKUP_FILE]: 'enum DemoMode {}' }
  assert.deepEqual(appPriceProblems(files, PRICES), [`Apps/${MAC_MOCKUP_FILE}: the Mac mock-up's price must be static let mockupPrice = "$1.99"`])
})

test('the iOS fake store still needs the iOS price', () => {
  const files = { ...base(), [IOS_FAKE_STORE_FILE]: IOS_OK.replace('4.99', '1.99') }
  assert.equal(appPriceProblems(files, PRICES).length, 2)
})

test('prices in other forms are caught', () => {
  for (const s of ['"1,99 €"', '"2.49 USD"', '"$ 3.00"', '"Unlock · $1.99"']) {
    assert.equal(appPriceProblems({ ...base(), 'Spike/Sources/X.swift': `let a = ${s}` }, PRICES).length, 1, s)
  }
})
