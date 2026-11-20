#!/usr/bin/env node
// Build self-contained single-file copies of one language's pages, for review by
// people who should get a file, not a link (e.g. a family Hebrew review, #265).
//
//   node scripts/build-site.mjs
//   node scripts/build-standalone.mjs he <out-dir>
//
// Each output opens by double-click from disk with no server: scripts are bundled
// (module imports fail on file://), stylesheets inlined, fonts and images become
// data: URIs, sibling pages link to each other, everything else goes to the live site.
import { readFileSync, writeFileSync, mkdirSync, existsSync } from 'node:fs'
import { dirname, join, resolve, extname } from 'node:path'
import { fileURLToPath } from 'node:url'
import { createRequire } from 'node:module'

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..')
const SITE = join(ROOT, 'site')
const LIVE = 'https://seal-speak.gileskayo.me/'
const PAGES = { index: 'home', support: 'support', privacy: 'privacy' }
const MAX_BYTES = 15 * 1024 * 1024
const MIME = { '.woff': 'font/woff', '.woff2': 'font/woff2', '.svg': 'image/svg+xml', '.png': 'image/png', '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg' }

function loadEsbuild () {
  const tries = [ROOT, join(process.env.HOME, '.agents/dashboard')]
  for (const base of tries) {
    try { return createRequire(join(base, 'package.json'))('esbuild') } catch { /* next */ }
  }
  throw new Error('esbuild not found (looked in the repo and ~/.agents/dashboard)')
}

export function dataUri (file) {
  const type = MIME[extname(file).toLowerCase()]
  if (!type) throw new Error(`no MIME type for ${file}`)
  return `data:${type};base64,${readFileSync(file).toString('base64')}`
}

// Resolve a page-relative reference ("../assets/x.png") to a file under site/.
function local (pageDir, ref) {
  const p = resolve(pageDir, ref.split(/[?#]/)[0])
  if (!p.startsWith(SITE + '/')) throw new Error(`${ref} escapes site/`)
  if (!existsSync(p)) throw new Error(`${ref} → ${p} is missing`)
  return p
}

export function rewriteLink (href, lang) {
  if (/^([a-z]+:|#|\/\/)/i.test(href)) return href // absolute, mailto:, in-page
  const [path, hash = ''] = href.split('#')
  const frag = hash ? `#${hash}` : ''
  const name = path.replace(/^\.\//, '')
  if (name === '' && href.startsWith('#')) return href
  if (name === '' || name === 'index.html') return `seal-speak-${lang}-home.html${frag}`
  const m = name.match(/^(support|privacy)\.html$/)
  if (m) return `seal-speak-${lang}-${PAGES[m[1]]}.html${frag}`
  // Anything else (other languages, versions page) goes to the live site.
  return new URL(href, `${LIVE}${lang}/`).href
}

export async function standalone (lang, page, esbuild) {
  const pageDir = join(SITE, lang)
  const file = join(pageDir, `${page}.html`)
  let html = readFileSync(file, 'utf8')

  // 1. Scripts: bundle each module into one inline <script type="module">.
  const scripts = [...html.matchAll(/<script type="module" src="([^"]+)"><\/script>/g)]
  for (const [tag, src] of scripts) {
    const out = await esbuild.build({ entryPoints: [local(pageDir, src)], bundle: true, format: 'esm', write: false, minify: false, logLevel: 'silent' })
    const code = out.outputFiles[0].text.replace(/<\/script/gi, '<\\/script')
    html = html.replace(tag, () => `<script type="module">\n${code}</script>`)
  }
  if (/<script[^>]+src=/.test(html)) throw new Error(`${file}: a script tag kept its src`)

  // 2. Stylesheets: inline as <style>, with their own url() refs embedded.
  html = html.replace(/<link rel="stylesheet" href="([^"]+)">/g, (_, href) => {
    const cssFile = local(pageDir, href)
    const css = readFileSync(cssFile, 'utf8').replace(/url\((['"]?)(?!data:|https?:|#)([^'")]+)\1\)/g,
      (__, q, ref) => `url('${dataUri(local(dirname(cssFile), ref))}')`)
    return `<style>\n${css}\n</style>`
  })

  // 3. url() refs in the page's own <style> (the @font-face fonts).
  html = html.replace(/url\((['"]?)(?!data:|https?:|#)([^'")]+)\1\)/g, (_, q, ref) => `url('${dataUri(local(pageDir, ref))}')`)

  // 4. Images and icon links.
  html = html.replace(/(<img\b[^>]*?\ssrc=")([^"]+)(")/g, (all, a, src, b) =>
    /^(data:|https?:)/.test(src) ? all : a + dataUri(local(pageDir, src)) + b)
  html = html.replace(/(<link\b[^>]*rel="(?:icon|apple-touch-icon|shortcut icon)"[^>]*?\shref=")([^"]+)(")/g, (all, a, href, b) =>
    /^(data:|https?:)/.test(href) ? all : a + dataUri(local(pageDir, href)) + b)
  html = html.replace(/(<link\b[^>]*?\shref=")([^"]+)("[^>]*rel="(?:icon|apple-touch-icon)")/g, (all, a, href, b) =>
    /^(data:|https?:)/.test(href) ? all : a + dataUri(local(pageDir, href)) + b)

  // 5. Remaining relative links: siblings stay local, the rest go live.
  html = html.replace(/(<a\b[^>]*?\shref=")([^"]+)(")/g, (_, a, href, b) => a + rewriteLink(href, lang) + b)
  html = html.replace(/(<link\b[^>]*?\shref=")([^"]+)(")/g, (all, a, href, b) =>
    /^(data:|https?:)/.test(href) ? all : a + rewriteLink(href, lang) + b)

  if (!/<meta name="robots" content="noindex/.test(html)) {
    html = html.replace('<head>', '<head>\n<meta name="robots" content="noindex, nofollow">')
  }
  const leftover = [...html.matchAll(/(?:src|href)="(\.\.?\/[^"]*)"/g)].map((m) => m[1])
  if (leftover.length) throw new Error(`${file}: relative refs left: ${leftover.join(', ')}`)
  return html
}

async function main () {
  const [lang, outDir] = process.argv.slice(2)
  if (!lang || !outDir) { console.error('usage: build-standalone.mjs <lang> <out-dir>'); process.exit(2) }
  const esbuild = loadEsbuild()
  mkdirSync(outDir, { recursive: true })
  for (const [page, name] of Object.entries(PAGES)) {
    const html = await standalone(lang, page, esbuild)
    const bytes = Buffer.byteLength(html)
    if (bytes > MAX_BYTES) throw new Error(`${page}: ${bytes} bytes is over ${MAX_BYTES}`)
    const out = join(outDir, `seal-speak-${lang}-${name}.html`)
    writeFileSync(out, html)
    console.log(`standalone: ${out} (${(bytes / 1024).toFixed(0)} KB)`)
  }
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main().catch((e) => { console.error(`standalone: ${e.message}`); process.exit(1) })
}
