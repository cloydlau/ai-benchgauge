// Test instrumentation: identify executed source copies by exact bytes, including
// copies that fixtures delete before Node produces its coverage summary.
const fs = require('node:fs')
const path = require('node:path')
const { pathToFileURL } = require('node:url')
const { createHash } = require('node:crypto')
const { registerHooks } = require('node:module')
const root = process.env.BENCHGAUGE_COVERAGE_ROOT
const directory = process.env.BENCHGAUGE_COVERAGE_DIRECTORY
if (root && directory) {
  if (typeof registerHooks !== 'function') throw new Error('This Node runtime does not support source-aware coverage collection')
  const hashes = new Map(), originals = {}
  const digest = bytes => createHash('sha256').update(bytes).digest('hex')
  for (const name of fs.readdirSync(path.join(root, 'Scripts'))) {
    if (!name.endsWith('.mjs') || name.endsWith('.test.mjs')) continue
    const source = pathToFileURL(path.join(root, 'Scripts', name)).href
    const hash = digest(fs.readFileSync(path.join(root, 'Scripts', name)))
    originals[source] = hash
    const candidates = hashes.get(hash) || []
    candidates.push(source); hashes.set(hash, candidates)
  }
  const aliases = []
  fs.mkdirSync(directory, { recursive: true })
  const manifest = path.join(directory, `sources-${process.pid}.json`)
  const save = () => fs.writeFileSync(manifest, JSON.stringify({ originals, aliases }))
  save()
  registerHooks({ load(url, context, next) {
    const result = next(url, context)
    if (result.source != null) {
      const hash = digest(result.source)
      const candidates = hashes.get(hash)
      if (candidates?.length === 1 && candidates[0] !== url) {
        aliases.push({ target: url, source: candidates[0], sha256: hash })
        save()
      }
    }
    return result
  } })
}
