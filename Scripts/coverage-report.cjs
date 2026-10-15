const fs = require('node:fs')
const path = require('node:path')
const { fileURLToPath } = require('node:url')
const { createHash } = require('node:crypto')

function normalizeProfiles(directory, root) {
  const aliases = new Map()
  const originals = new Map()
  const digest = source => createHash('sha256').update(source).digest('hex')
  for (const name of fs.readdirSync(directory).filter(name => name.startsWith('sources-'))) {
    const manifest = JSON.parse(fs.readFileSync(path.join(directory, name), 'utf8'))
    for (const [url, hash] of Object.entries(manifest.originals)) {
      if (digest(fs.readFileSync(fileURLToPath(url))) !== hash) throw Error(`Source changed during coverage: ${url}`)
      originals.set(url, hash)
    }
    for (const alias of manifest.aliases) {
      if (originals.get(alias.source) !== alias.sha256) throw Error(`Unverified coverage alias: ${alias.target}`)
      aliases.set(alias.target, alias.source)
    }
  }
  if (!originals.size) throw Error('Missing execution source manifests')
  const target = path.join(directory, 'normalized')
  fs.mkdirSync(target, { recursive: true })
  const files = fs.readdirSync(directory).filter(name => /^coverage-\d+-\d+-\d+\.json$/.test(name))
  if (!files.length) throw Error('Missing V8 execution profiles')
  for (const name of files) {
    const profile = JSON.parse(fs.readFileSync(path.join(directory, name), 'utf8'))
    profile.result = profile.result.flatMap(script => {
      script.url = aliases.get(script.url) || script.url
      return originals.has(script.url) ? [script] : []
    })
    fs.writeFileSync(path.join(target, name), JSON.stringify(profile))
  }
  return target
}

function validateCoverage(coverage) {
  if (!Array.isArray(coverage?.files) || !coverage.files.length) throw Error('The merged script coverage report is empty')
  for (const file of coverage.files) {
    for (const metric of ['Line', 'Branch', 'Function']) {
      const covered = file[`covered${metric}Count`], total = file[`total${metric}Count`]
      if (!Number.isInteger(covered) || !Number.isInteger(total) || total < 0 || covered < 0 || covered > total) {
        throw Error(`Invalid ${metric.toLowerCase()} coverage counts: ${file.path}`)
      }
      if (covered !== total) throw Error(`Coverage must be 100% for every file and metric: ${file.path} ${metric.toLowerCase()} ${covered}/${total}`)
    }
  }
  return coverage
}

function collectCoverage(directory, root) {
  const { TestCoverage } = require('internal/test_runner/coverage')
  const normalized = normalizeProfiles(directory, root)
  const coverage = new TestCoverage(normalized, null, {
    cwd: root,
    coverageIncludeGlobs: [path.join(root, 'Scripts', '*.mjs')],
    coverageExcludeGlobs: ['**/*.test.mjs'],
  }).summary()
  if (!coverage.files.length) throw Error('The merged script coverage report is empty')
  fs.writeFileSync(path.join(directory, 'summary.json'), JSON.stringify(coverage, null, 2) + '\n')
  for (const file of coverage.files) {
    console.log(`[coverage] ${path.basename(file.path)}: lines ${file.coveredLineCount}/${file.totalLineCount}, branches ${file.coveredBranchCount}/${file.totalBranchCount}, functions ${file.coveredFunctionCount}/${file.totalFunctionCount}`)
  }
  return validateCoverage(coverage)
}

module.exports = { normalizeProfiles, collectCoverage, validateCoverage }
if (require.main === module) {
  try { collectCoverage(path.resolve(process.argv[2]), path.resolve(process.argv[3])) }
  catch (error) { console.error(error.message); process.exitCode = 1 }
}
