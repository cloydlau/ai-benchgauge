import assert from 'node:assert/strict'
import test from 'node:test'
import { boards, categories, copy, languages, text } from '../src/core/catalog.js'
import { normalizeBoard, canReplace, countryCode, countryFlag, countryOptions, companyRows, visibleRows, formatTime, rowView } from '../src/core/leaderboard.js'

const kind = 'artificialAnalysis'
const entry = (rank, name, score, organization, fields = {}) => ({ rank, name, score, organization, ...fields })
const board = (entries, fields = {}) => ({ kind, fetchedAt: '2026-10-13T12:00:00Z', entries, ...fields })

test('the four categories cover exactly the eight existing shared API kinds and all translations', () => {
  assert.equal(categories.length, 4)
  assert.deepEqual(categories.flatMap(item => item.kinds).sort(), Object.keys(boards).sort())
  for (const values of Object.values(copy)) for (const language of languages) assert.ok(text(values, language))
  assert.equal(text(copy.tasks, 'zh-CN'), '任务测评')
  assert.equal(text(copy.votes, 'zh-TW'), '使用者盲測')
})
test('normalization rejects wrong sources, duplicate ranks, malformed timestamps and partial invalid rows', () => {
  const valid = board([entry(2, 'Second', 88, 'A'), entry(1, 'First', 90, 'A')])
  assert.deepEqual(normalizeBoard(valid, kind).entries.map(entry => entry.rank), [1, 2])
  for (const value of [null, { ...valid, kind: 'arenaText' }, { ...valid, fetchedAt: 'bad' },
    { ...valid, sourceUpdatedAt: 'bad' }, board([]), board([entry(1, 'A', 1, 'A'), entry(1, 'B', 2, 'B')]),
    board([entry(0, 'A', 1, 'A')]), board([entry(1, '', 1, 'A')]), board([entry(1, 'A', Infinity, 'A')])]) {
    assert.throws(() => normalizeBoard(value, kind))
  }
  assert.throws(() => normalizeBoard(valid, 'constructor'))
  assert.equal(normalizeBoard(board([entry(1, 'A', 1, 'A', { openness: 'noncommercial' })]), kind).entries[0].openness, null)
})
test('fetch and source publication times independently prevent stale snapshots replacing cache', () => {
  const entries = [entry(1, 'A', 1, 'A')]
  const old = board(entries, { sourceUpdatedAt: '2026-10-12T12:00:00Z' })
  assert.equal(canReplace(old, null), true)
  assert.equal(canReplace(old, old), true)
  for (const next of [board(entries, { fetchedAt: '2026-10-11T12:00:00Z' }),
    board(entries), board(entries, { sourceUpdatedAt: '2026-10-11T12:00:00Z' }), { ...old, kind: 'arenaText' }]) assert.ok(!canReplace(next, old))
  assert.equal(canReplace({ ...old, fetchedAt: '2026-10-14T12:00:00Z' }, old), true)
  assert.equal(formatTime(null), '—')
  assert.equal(formatTime('bad'), '—')
  assert.notEqual(formatTime(old.fetchedAt), formatTime(old.sourceUpdatedAt))
})
test('company scores use the strongest filtered model, never averages or model counts', () => {
  const entries = [entry(1, 'Best A', 100, 'OpenAI'), entry(2, 'Best B', 99, 'Anthropic'),
    entry(3, 'Weaker A', 5, 'Open AI'), entry(4, 'B sibling', 2, 'Anthropic'),
    entry(5, 'Third', 99, 'Third'), entry(6, 'Unknown harness', 101, null)]
  const rows = companyRows(entries)
  assert.deepEqual(rows.map(row => [row.name, row.score, row.rank]), [['OpenAI', 100, 1], ['Anthropic', 99, 2], ['Third', 99, 3]])
  assert.equal(rows[0].components.length, 2)
  const filtered = visibleRows(board(entries.map((e, i) => ({ ...e, openness: i === 0 ? 'closed' : 'open' }))), { grouping: 'company', openness: 'open' })
  assert.deepEqual(filtered.map(row => [row.name, row.score]), [['Anthropic', 99], ['Third', 99], ['OpenAI', 5]])
})

test('the country list accepts new ISO countries without guessing their translated names', () => {
  const options = countryOptions(board([entry(1, 'New', 1, 'New', { developerCountry: { countryCode: 'AU' } })]), 'en')
  assert.equal(options[1].label, '🇦🇺 AU')
})
test('provider identity and company graphics remain distinct from model-family graphics', () => {
  const model = entry(1, 'Wan model', 90, 'Alibaba', { brand: { key: 'model-wan', colorHex: '#111111' },
    organizationBrand: { key: 'qwen', colorHex: '#222222' } })
  assert.equal(companyRows([model])[0].brand.key, 'qwen')
  assert.equal(companyRows([entry(1, 'Claude agent', 99, null, { developerCountry: { key: 'anthropic', countryCode: 'US' } })]).length, 0)
  assert.equal(companyRows([entry(1, 'Named', 1, 'constructor')])[0].name, 'constructor')
})

test('company country inherits verified company metadata and does not borrow a harness model provider', () => {
  const country = { key: 'openai', countryCode: 'US' }
  const rows = companyRows([entry(1, 'Best', 99, 'OpenAI'), entry(2, 'Other', 90, 'Open AI', { developerCountry: country })])
  assert.deepEqual(rows[0].developerCountry, country)
  assert.equal(companyRows([entry(1, 'Agent', 99, 'Unlisted Harness', { developerCountry: country })])[0].developerCountry, undefined)
})

test('native organization aliases do not split a company into duplicate standings', () => {
  for (const [a, b, name] of [['Moonshot', 'Moonshot AI', 'Moonshot'], ['Alibaba', 'Alibaba ATH', 'Alibaba'],
    ['ByteDance', 'ByteDance Seed', 'ByteDance'], ['Luma AI', 'Luma Labs', 'Luma']]) {
    const rows = companyRows([entry(1, 'Best', 99, a), entry(2, 'Other', 80, b)])
    assert.equal(rows.length, 1); assert.equal(rows[0].name, name); assert.equal(rows[0].score, 99)
  }
})
test('country and openness filters intersect, unknown metadata stays explicit, model ranks remain original', () => {
  const input = board([
    entry(1, 'Closed US', 100, 'A', { openness: 'closed', developerCountry: { countryCode: 'US' } }),
    entry(2, 'Open US', 99, 'B', { openness: 'open', developerCountry: { countryCode: 'us' } }),
    entry(3, 'Open CN', 98, 'C', { openness: 'open', developerCountry: { countryCode: 'CN' } }),
    entry(4, 'Unknown', 97, 'D'),
  ])
  assert.deepEqual(visibleRows(input, { country: 'US', openness: 'open' }).map(row => row.rank), [2])
  assert.deepEqual(visibleRows(input, { country: 'unknown', openness: 'unknown' }).map(row => row.rank), [4])
  assert.deepEqual(countryOptions(input, 'zh-CN').map(option => option.value), ['all', 'CN', 'US', 'unknown'])
  assert.equal(countryCode({ developerCountry: { countryCode: 12 } }), 'unknown')
  assert.equal(countryFlag('US'), '🇺🇸')
  assert.equal(countryFlag('unknown'), '—')
  assert.equal(visibleRows(null).length, 0)
})
test('the view DTO contains only display fields and uses PNG data rather than arbitrary remote image URLs', () => {
  const original = entry(1, 'A', 95.56, 'A', { logoURL: 'https://untrusted.invalid/a.png',
    brand: { key: 'model-verified', pngData: 'iVBORw0KGgo=', colorHex: '#112233' } })
  const view = rowView(original)
  assert.equal(view.logo, 'data:image/png;base64,iVBORw0KGgo=')
  assert.equal(view.scoreText, '95.6')
  assert.equal(view.brand, undefined)
  assert.equal(view.logoURL, undefined)
  assert.notEqual(rowView(original, { dark: true }).fill, view.fill)
  assert.equal(rowView({ ...original, brand: { pngData: '<script>', colorHex: 'bad' } }).logo, '')
  assert.equal(rowView({ ...original, brand: { key: 'openai' } }).logo, '')
  assert.equal(rowView({ ...original, name: 'Claude Sonnet', organization: 'Anthropic', brand: { key: 'anthropic', pngData: 'iVBORw0KGgo=' } }).logo, '/assets/logos/anthropic.png')
})

test('complete model and company lists include rows beyond twenty and five hundred', () => {
  const entries = Array.from({ length: 601 }, (_, index) => entry(index + 1, `Model ${index + 1}`, 1000 - index, `Maker ${index + 1}`))
  const complete = normalizeBoard(board(entries), kind)
  assert.equal(visibleRows(complete).length, 601)
  assert.equal(visibleRows(complete).at(-1).name, 'Model 601')
  const companies = visibleRows(complete, { grouping: 'company' })
  assert.equal(companies.length, 601)
  assert.equal(companies.at(-1).rank, 601)
})
