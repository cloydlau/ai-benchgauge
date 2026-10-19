import assert from 'node:assert/strict'
import { spawn } from 'node:child_process'
import { mkdtempSync, mkdirSync, writeFileSync, rmSync, readFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { createInterface } from 'node:readline'
const executable = process.argv[2]
if (!executable) throw new Error('Pass the packaged engine executable')
const root = mkdtempSync(join(tmpdir(), 'benchgauge-engine-'))
const cache = join(root, 'leaderboards.json')
writeFileSync(cache, JSON.stringify({ boards: { arenaText: { kind: 'arenaText', title: 'fixture', fetchedAt: '2026-09-29T00:00:00Z', entries: [{ rank: 1, name: 'GPT fixture', score: 100, organization: 'OpenAI', openness: 'closed' }, { rank: 2, name: 'DeepSeek open', score: 90, organization: 'DeepSeek', openness: 'open' }, { rank: 3, name: 'GPT open', score: 80, organization: 'OpenAI', openness: 'open' }, { rank: 4, name: 'Claude unknown', score: 70, organization: 'Anthropic' }] } } }))
const child = spawn(executable, ['--cache-file', cache], { stdio: ['pipe', 'pipe', 'pipe'] })
const deadline = setTimeout(() => child.kill(), 15_000)
const exited = new Promise((resolve, reject) => { child.on('error', reject); child.on('close', resolve) })
const model = JSON.parse(readFileSync(new URL('../Tests/fixtures/model-details.json', import.meta.url))).entry.modelMetadata
const requests = [
  { id: 17, command: 'state', language: 'en', category: 'general' },
  { id: 18, command: 'state', language: 'en', category: 'general', sources: { arenaText: 'open' } },
  { id: 19, command: 'state', language: 'en', category: 'general', grouping: 'company', sources: { arenaText: 'open' }, countries: { arenaText: 'unitedStates' } },
  { id: 20, command: 'state', language: 'en', category: 'general', sources: { arenaText: 'unknown' } },
  { id: 21, command: 'state', language: 'en', category: 'general', sources: { arenaText: 'closed' }, countries: { arenaText: 'china' } },
]
requests.push({ id: 22, command: 'modelDetails', language: 'zh', pageText: JSON.stringify(model) })
const responses = []
const lines = createInterface({ input: child.stdout })
child.stdin.end(requests.map(request => JSON.stringify(request)).join('\n') + '\n')
try {
  for await (const line of lines) responses.push(JSON.parse(line))
  assert.equal(await exited, 0)
  assert.equal(responses.length, requests.length)
  responses.sort((left, right) => left.id - right.id)
  responses.forEach((response, index) => {
    assert.equal(response.id, requests[index].id)
    if (response.id !== 22) assert.deepEqual(response.result.quotas, [])
    else assert.equal(response.result, undefined)
    assert.equal(response.error, undefined)
  })
  const rows = responses.filter(response => response.result).map(response => response.result.boards[1].entries)
  assert.equal(rows[0][0].name, 'GPT fixture')
  assert.equal(rows[0][0].country, 'unitedStates')
  assert.deepEqual(rows[1].map(row => row.name), ['DeepSeek open', 'GPT open'])
  assert.equal(rows[2].length, 1)
  assert.equal(rows[2][0].organization, 'OpenAI')
  assert.equal(rows[2][0].score, 80)
  assert.equal(rows[2][0].openness, undefined)
  assert.deepEqual(rows[3].map(row => row.name), ['Claude unknown'])
  assert.deepEqual(rows[4], [])
  assert.equal(responses.find(r => r.id === 22).modelDetails[0].title, '模型资料')
  assert.ok(responses.find(r => r.id === 22).modelDetails.some(s => s.id === 'provider-0'))
  console.log('PASS: engine JSON round trips, source/country intersection and filtering before company aggregation')
} finally { clearTimeout(deadline); rmSync(root, { recursive: true, force: true }) }
