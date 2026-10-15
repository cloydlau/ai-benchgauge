const fs = require('node:fs')
const path = require('node:path')

function reportPaths(root) {
  const scratch = path.join(root, 'work', 'unit-test-build')
  const candidates = [path.join(scratch, 'out', 'Products', 'Debug', 'codecov', 'AI-BenchGauge.json')]
  if (fs.existsSync(scratch)) {
    for (const entry of fs.readdirSync(scratch, { withFileTypes: true })) {
      if (entry.isDirectory()) candidates.push(path.join(scratch, entry.name, 'debug', 'codecov', 'AI-BenchGauge.json'))
    }
  }
  return candidates.filter(file => fs.existsSync(file))
}

function sourcePaths(root) {
  // Preserve the existing default Swift report: the two unit-tested libraries.
  // The bridge entry point and separately merged native UI binaries are not in it.
  const paths = []
  for (const library of ['LeaderboardCore', 'LeaderboardKit']) {
    const directory = path.join(root, 'Sources', library)
    for (const name of fs.readdirSync(directory)) {
      if (!name.endsWith('.swift')) continue
      const file = path.join(directory, name)
      const source = fs.readFileSync(file, 'utf8').replace(/\/\/[^\n]*/g, '').trim()
      if (source === '@_exported import LeaderboardKit') continue // No executable code.
      paths.push(file)
    }
  }
  return paths.sort()
}

function validateSwiftCoverage(report, expected) {
  if (report?.type !== 'llvm.coverage.json.export' || !Array.isArray(report.data) || report.data.length !== 1) throw Error('Invalid Swift coverage report')
  const files = report.data[0].files
  if (!Array.isArray(files) || !expected.length) throw Error('Empty Swift coverage scope')
  const measured = files.filter(file => expected.includes(file.filename))
  if (measured.length !== expected.length || new Set(measured.map(file => file.filename)).size !== expected.length) throw Error('Missing or duplicate Swift coverage source files')
  const totals = Object.fromEntries(['lines', 'functions', 'regions'].map(metric => [metric, 0]))
  for (const file of measured) {
    for (const metric of Object.keys(totals)) {
      const item = file.summary?.[metric]
      if (!Number.isInteger(item?.count) || !Number.isInteger(item?.covered) || item.count < 0 || item.covered < 0 || item.covered > item.count) throw Error(`Invalid Swift ${metric} counts: ${file.filename}`)
      if (item.covered !== item.count) throw Error(`Swift coverage must be 100% for every file and metric: ${file.filename} ${metric} ${item.covered}/${item.count}`)
      totals[metric] += item.count
    }
  }
  return { files: measured.length, totals }
}

module.exports = { reportPaths, sourcePaths, validateSwiftCoverage }
if (require.main === module) {
  try {
    const root = fs.realpathSync(path.resolve(process.argv[2]))
    if (process.argv[3] === '--clear') {
      for (const file of reportPaths(root)) fs.rmSync(file)
    } else {
      const reports = reportPaths(root)
      if (reports.length !== 1) throw Error('Require exactly one freshly generated default Swift coverage report')
      const result = validateSwiftCoverage(JSON.parse(fs.readFileSync(reports[0], 'utf8')), sourcePaths(root))
      console.log(`[coverage] Swift ${result.files} source files: ` + Object.entries(result.totals).map(([metric, count]) => `${metric} ${count}/${count}`).join(', '))
    }
  } catch (error) { console.error(error.message); process.exitCode = 1 }
}
