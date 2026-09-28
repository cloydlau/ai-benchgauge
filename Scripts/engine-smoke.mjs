import assert from 'node:assert/strict'
import { spawn } from 'node:child_process'
import { mkdtempSync, mkdirSync, writeFileSync, rmSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
const executable = process.argv[2]
if (!executable) throw new Error('Pass the packaged engine executable')
const root = mkdtempSync(join(tmpdir(), 'benchgauge-engine-'))
const cache = join(root, 'leaderboards.json')
writeFileSync(cache, JSON.stringify({ boards: { arenaText: { kind: 'arenaText', title: 'fixture', fetchedAt: '2026-09-29T00:00:00Z', entries: [{ rank: 1, name: 'GPT fixture', score: 100, organization: 'OpenAI' }] } } }))
const child = spawn(executable, ['--cache-file', cache], { stdio: ['pipe', 'pipe', 'pipe'] })
const deadline = setTimeout(() => child.kill(), 15_000)
let output = ''; let finished = false
child.stdout.on('data', chunk => {
  output += chunk
  if (output.includes('\n') && !finished) {
    finished = true
    const response = JSON.parse(output.split('\n')[0]); assert.equal(response.id, 17)
    assert.equal(response.result.boards[1].entries[0].name, 'GPT fixture')
    assert.equal(response.result.boards[1].entries[0].country, 'unitedStates')
    assert.deepEqual(response.result.quotas, [])
    assert.equal(response.error, undefined)
    child.stdin.end()
  }
})
child.stdin.write(JSON.stringify({ id: 17, command: 'state', language: 'en', category: 'general' }) + '\n')
try {
  const code = await new Promise((resolve, reject) => { child.on('error', reject); child.on('close', resolve) })
  assert.equal(code, 0); assert.ok(finished)
  console.log('PASS: packaged engine JSON round trip with synthetic cached leaderboard, no account queries')
} finally { clearTimeout(deadline); rmSync(root, { recursive: true, force: true }) }
