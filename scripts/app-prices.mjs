// The app's price rule (#228; the Mac mock-up, #231), used by check-site.mjs section 10.
// The app shows StoreKit's displayPrice, so no Swift or string file hard-codes a price, with exactly two exceptions,
// each one line built from PRICES: the iPhone's debug fake store (TranslationCenter.swift, the iOS price) and the Mac
// screenshot mock-up's price (the Mac's DemoMode, the Mac price) until the Mac's StoreKit purchase is wired (#213).
export const IOS_FAKE_STORE_FILE = 'Spike/Sources/TranslationCenter.swift'
export const MAC_MOCKUP_FILE = 'Mac/Sources/IPhoneViewShims.swift'
export const FAKE_STORE_IOS = (prices) => `price = "$${prices.translationIOS}"`
export const MOCKUP_MAC = (prices) => `static let mockupPrice = "$${prices.translationMac}"`

const PRICE = /"[^"]*(\$\s?\d+[.,]\d\d|\d[.,]\d\d\s?(\$|USD|€|£))[^"]*"/
const PRICES_ON_LINE = new RegExp(PRICE.source, 'g')

// files: { 'Spike/Sources/X.swift': text, ... } (paths under Apps/). Returns the problems, in order.
export function appPriceProblems(files, prices) {
  const problems = []
  const fake = FAKE_STORE_IOS(prices), mockup = MOCKUP_MAC(prices)
  // A sanctioned line holds its one price and nothing else priced.
  const sanctioned = (f, l) => (l.match(PRICES_ON_LINE) || []).length === 1 && (
    (f === IOS_FAKE_STORE_FILE && l.includes('DemoMode.fakeStore') && l.includes(fake)) ||
    (f === MAC_MOCKUP_FILE && l.trim() === mockup))
  for (const [f, text] of Object.entries(files)) {
    const lines = text.split('\n')
    if (f === IOS_FAKE_STORE_FILE && !lines.some((l) => sanctioned(f, l))) problems.push(`Apps/${f}: the fake store's price must be ${fake}`)
    if (f === MAC_MOCKUP_FILE && !lines.some((l) => sanctioned(f, l))) problems.push(`Apps/${f}: the Mac mock-up's price must be ${mockup}`)
    for (const [i, l] of lines.entries()) {
      if (PRICE.test(l) && !sanctioned(f, l)) problems.push(`Apps/${f}:${i + 1} hard-codes a price; show StoreKit's displayPrice`)
    }
  }
  return problems
}
