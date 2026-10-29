// The evidence log, one file per entry in docs/research/evidence/ (#210), no dependencies.
//   node scripts/check-evidence.mjs          check every entry (CI runs this)
//   node scripts/check-evidence.mjs --print  the whole log as one page, for the portfolio and marketing pages
// E01-E29 keep the numbers they were cited by. New entries are YYYY-MM-DD-<slug>.md with a plain "# Title", so two
// branches adding evidence never pick the same number or edit the same file.
import { readFileSync, readdirSync } from 'fs'
import path from 'path'
import { fileURLToPath } from 'url'

const ROOT = path.join(path.dirname(fileURLToPath(import.meta.url)), '..')
export const DIR = path.join(ROOT, 'docs/research/evidence')
const FIELDS = ['**Source', '**What we took:**', '**Confidence:**', '**Drives:**', '**Public use:**']
const NUMBERED = /^E(\d{2})-[a-z0-9-]+\.md$/
const DATED = /^\d{4}-\d{2}-\d{2}-[a-z0-9-]+\.md$/
const LAST_NUMBERED = 29

const entries = dir => readdirSync(dir).filter(f => f.endsWith('.md')).sort()

export function problems(dir = DIR) {
  const out = []
  for (const file of entries(dir)) {
    const text = readFileSync(path.join(dir, file), 'utf8')
    const numbered = file.match(NUMBERED)
    if (!(numbered && Number(numbered[1]) <= LAST_NUMBERED) && !DATED.test(file)) {
      out.push(`${file}: new entries are named YYYY-MM-DD-<slug>.md (E01-E${LAST_NUMBERED} are the only numbered ones)`)
      continue
    }
    const first = text.split('\n')[0]
    if (!first.startsWith('# ')) { out.push(`${file}: first line must be a "# " heading`); continue }
    if (numbered && !first.startsWith(`# E${Number(numbered[1])}. `)) out.push(`${file}: heading must start with "E${Number(numbered[1])}. "`)
    // Source is "**Source:**" or "**Sources:**"; the rest are exact
    for (const f of FIELDS) if (!text.includes(f)) out.push(`${file}: missing ${f === '**Source' ? '**Source:**' : f}`)
  }
  return out
}

export function combined(dir = DIR) {
  const files = entries(dir)
  const ordered = [
    ...files.filter(f => NUMBERED.test(f)).sort((a, b) => parseInt(a.slice(1)) - parseInt(b.slice(1))),
    ...files.filter(f => DATED.test(f)),
  ]
  const intro = readFileSync(path.join(ROOT, 'docs/research/evidence-log.md'), 'utf8').split('\n## Where the entries are')[0]
  return [intro.trimEnd(), ...ordered.map(f => '#' + readFileSync(path.join(dir, f), 'utf8').trimEnd())].join('\n\n') + '\n'
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  if (process.argv.includes('--print')) {
    process.stdout.write(combined())
  } else {
    const found = problems()
    for (const p of found) console.error(`evidence: ${p}`)
    console.log(found.length ? `${found.length} problem(s)` : `${entries(DIR).length} evidence entries OK`)
    process.exit(found.length ? 1 : 0)
  }
}
