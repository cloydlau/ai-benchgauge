import assert from 'node:assert/strict'
import test from 'node:test'
import { existsSync, readFileSync } from 'node:fs'
import brandCatalog from '../../../fc/brand-catalog.json' with { type: 'json' }
import { boards, categories, copy, languages, text } from '../src/core/catalog.js'
import { normalizeBoard, canReplace, countryCode, countryFlag, countryOptions, companyRows, visibleRows, formatTime, rowView, scoreShareText, modelNameMatches } from '../src/core/leaderboard.js'

const kind = 'artificialAnalysis'
const entry = (rank, name, score, organization, fields = {}) => ({ rank, name, score, organization, ...fields })
const board = (entries, fields = {}) => ({ kind, fetchedAt: '2026-10-13T12:00:00Z', entries, ...fields })

test('cached Epoch rows share verified source badges and filtering while keeping hosted and public releases distinct', () => {
  const ids = ['Gemini 4 Argon', 'Qwen 3.6 Max (Preview)', 'Mistral Large 4',
    'Qwen 3.5 Plus (hosted 397B-A17B)', 'Qwen 3.5 Flash (hosted 35B-A3B)', 'Qwen 3.6 Flash']
  const input = board([
    ...ids.map((id, index) => entry(index + 1, id, 160 - index, null, { modelID: id })),
    entry(7, 'Qwen3.5-397B-A17B', 147, 'Alibaba', { modelID: 'Qwen3.5-397B-A17B', openness: 'open' }),
    entry(8, 'Future variant', 145, null, { modelID: ids[0] + '-finetune' }),
  ], { kind: 'epochECI' })
  const original = structuredClone(input)
  for (const snapshot of [input, normalizeBoard(input, 'epochECI')]) {
    const rows = visibleRows(snapshot, { openness: 'closed' })
    assert.deepEqual(rows.map(row => row.name), ids)
    assert.ok(rows.every(row => row.openness === 'closed' && row.opennessIcon))
    assert.deepEqual(visibleRows(snapshot, { openness: 'open' }).map(row => row.rank), [7])
    assert.deepEqual(visibleRows(snapshot, { openness: 'unknown' }).map(row => row.rank), [8])
  }
  assert.deepEqual(input, original)
})

test('model search combines name tokens with existing filters, keeps ranks and the unsearched leader, and ignores company names', () => {
  const source = board([
    entry(1, 'Leader', 100, 'Alpha Labs', { openness: 'closed' }),
    entry(2, 'Alpha Pro', 80, 'Maker One', { openness: 'open' }),
    entry(3, 'Alpha Mini', 70, 'Maker Two', { openness: 'closed' }),
    entry(4, 'Beta', 60, 'Alpha Labs', { openness: 'open' }),
  ])
  assert.deepEqual(visibleRows(source, { query: '  ALPHA  pro ' }).map(row => [row.rank, row.name, row.scoreShare]), [[2, 'Alpha Pro', '80%']])
  assert.deepEqual(visibleRows(source, { query: 'alpha', openness: 'open' }).map(row => row.rank), [2])
  assert.equal(visibleRows(source, { query: 'Maker' }).length, 0)
  assert.deepEqual(visibleRows(source, { grouping: 'company', query: 'nothing' }), [])
  assert.equal(visibleRows(source, { query: ' \n ' }).length, 4)
  assert.equal(modelNameMatches('Café Ａlpha 中文模型', ' cafe alpha 中文 '), true)
})

test('company name search follows aggregation and preserves ranks, scores and complete members', () => {
  const source = board([
    entry(1, 'Leader', 100, 'OpenAI', { openness: 'closed', developerCountry: { key: 'openai', countryCode: 'US' } }),
    entry(2, 'Beta', 80, 'DeepSeek', { openness: 'open', developerCountry: { key: 'deepseek', countryCode: 'CN' } }),
    entry(3, 'Gamma', 70, 'DeepSeek', { openness: 'closed', developerCountry: { key: 'deepseek', countryCode: 'CN' } }),
  ])
  const original = structuredClone(source)
  const [result] = visibleRows(source, { grouping: 'company', query: ' DEEP seek ' })
  assert.deepEqual([result.rank, result.name, result.score, result.scoreShare, result.fillPercent], [2, 'DeepSeek', 80, '80%', 80])
  assert.deepEqual(result.components.map(member => member.name), ['Beta', 'Gamma'])
  assert.deepEqual(visibleRows(source, { grouping: 'company', query: 'Beta' }), [], 'Search company names rather than member model names')
  assert.deepEqual(visibleRows(source, { grouping: 'company', country: 'US', query: 'DeepSeek' }), [])
  assert.equal(visibleRows(source, { grouping: 'company', country: 'CN', query: 'DeepSeek' })[0].score, 80)
  assert.equal(visibleRows(source, { grouping: 'company', openness: 'closed', query: 'DeepSeek' })[0].score, 70)
  const [usage] = visibleRows({ ...source, kind: 'openRouterUsage' }, { grouping: 'company', query: 'DeepSeek' })
  assert.equal(usage.score, 150, 'Usage search retains the sum of every member')
  assert.equal(usage.components.length, 2)
  assert.deepEqual(source, original)
})

test('score shares round consistently and omit leaders, near ties and invalid baselines', () => {
  for (const [score, leader, expected] of [[56, 57.6, '97%'], [97.5, 100, '98%'], [0, 100, '0%'],
    [100, 100, ''], [99.6, 100, ''], [101, 100, ''], [1, 0, ''], [-1, 100, ''],
    [NaN, 100, ''], [1, Infinity, ''], [Infinity, 1, ''], [1, undefined, '']]) {
    assert.equal(scoreShareText(score, leader), expected)
  }
  const source = board([entry(1, 'Closed', 100, 'OpenAI', { openness: 'closed' }),
    entry(2, 'Open A', 80, 'OpenAI', { openness: 'open' }),
    entry(3, 'Open B', 60, 'Anthropic', { openness: 'open' })])
  for (const grouping of ['model', 'company']) {
    assert.deepEqual(visibleRows(source, { grouping, openness: 'open' }).map(row => row.scoreShare), ['', '75%'])
  }
  assert.deepEqual(visibleRows(board([entry(1, 'A', 200), entry(2, 'B', 100)])).map(row => row.scoreShare), ['', '50%'])
})

test('ECI ratios use the filtered unsearched leader in model and company views, independent of score scale', () => {
  const source = board([
    entry(1, 'Leader', 150.25, 'OpenAI', { openness: 'closed' }),
    entry(2, 'Half', 75.125, 'Anthropic', { openness: 'open' }),
    entry(3, 'Quarter', 37.5625, 'DeepSeek', { openness: 'open' }),
  ], { kind: 'epochECI' })
  for (const grouping of ['model', 'company']) {
    const rows = visibleRows(source, { grouping })
    assert.deepEqual(rows.map(row => row.scoreShare), ['', '50%', '25%'])
    assert.deepEqual(rows.map(row => row.fillPercent), [100, 50, 25])
    assert.equal(rows[1].scoreText, '75.13')
    assert.deepEqual(visibleRows(source, { grouping, openness: 'open' }).map(row => row.scoreShare), ['', '50%'])
  }
  const searched = visibleRows(source, { query: 'Quarter' })
  assert.equal(searched[0].scoreShare, '25%')
  assert.equal(searched[0].fillPercent, 25)
})

test('score backgrounds use the unsearched leader, retain full leader width and handle unusable baselines', () => {
  const source = board([entry(1, 'Leader', 100), entry(2, 'Half', 50), entry(3, 'Zero', 0)])
  for (const dark of [false, true]) {
    assert.deepEqual(visibleRows(source, { dark }).map(row => row.fillPercent), [100, 50, 0])
    assert.equal(visibleRows(source, { dark, query: 'Half' })[0].fillPercent, 50)
  }
  for (const [score, leaderScore, expected] of [[99.6, 100, 99.6], [120, 100, 100], [5, 0, 100],
    [5, undefined, 100], [5, Infinity, 100], [-1, 100, 100]]) {
    assert.equal(rowView(entry(2, 'Model', score), { leaderScore }).fillPercent, expected)
  }
})

test('the five categories expose all active sources including restored Tencent', () => {
  assert.equal(categories.length, 5)
  assert.deepEqual(categories.flatMap(item => item.kinds).sort(), Object.keys(boards).filter(kind => kind !== 'openRouterPrice').sort())
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

test('the country list accepts new ISO countries and translates audited Australian and Russian developers', () => {
  const options = countryOptions(board([entry(1, 'New', 1, 'New', { developerCountry: { countryCode: 'NZ' } })]), 'en')
  assert.equal(options[1].label, '🇳🇿 NZ')
  const audited = board([
    entry(1, 'Lucid', 2, 'Leonardo AI', { developerCountry: { key: 'leonardoai', countryCode: 'AU' } }),
    entry(2, 'Kandinsky', 1, 'Kandinsky', { developerCountry: { key: 'kandinsky', countryCode: 'RU' } }),
  ])
  assert.deepEqual(countryOptions(audited, 'zh-CN').slice(1).map(option => option.label), ['🇦🇺 澳大利亚', '🇷🇺 俄罗斯'])
  assert.deepEqual(visibleRows(audited, { country: 'AU' }).map(row => row.name), ['Lucid'])
  assert.equal(visibleRows(audited, { grouping: 'company', country: 'RU' })[0].flag, '🇷🇺')
})
test('Hong Kong, Macao and Taiwan share China flags, country options and model/company filters even in old snapshots', () => {
  const cached = board(['CN', 'HK', 'MO', 'TW'].map((code, index) => entry(index + 1, `Model ${code}`, 100 - index, 'New Maker', {
    developerCountry: { key: 'newmaker', countryCode: code },
  })))
  assert.ok(normalizeBoard(cached, kind).entries.every(entry => entry.developerCountry.countryCode === 'CN'))
  for (const code of ['HK', 'MO', 'TW', 'CN']) {
    assert.equal(countryCode({ developerCountry: { countryCode: code } }), 'CN')
    assert.equal(countryFlag(code), '🇨🇳')
    for (const language of ['en', 'zh-CN', 'zh-TW']) {
      const options = countryOptions(cached, language, code)
      assert.deepEqual(options.map(option => option.value), ['all', 'CN'])
      assert.equal(options[1].label, `🇨🇳 ${language === 'en' ? 'China' : language === 'zh-CN' ? '中国' : '中國'}`)
    }
    const models = visibleRows(cached, { country: code })
    assert.equal(models.length, 4)
    assert.ok(models.every(row => row.flag === '🇨🇳'))
    const companies = visibleRows(cached, { grouping: 'company', country: code })
    assert.equal(companies.length, 1); assert.equal(companies[0].flag, '🇨🇳'); assert.equal(companies[0].score, 100)
  }
  assert.equal(companyRows(cached.entries.slice(1))[0].developerCountry.countryCode, 'CN')
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
  assert.equal(rowView({ ...original, name: 'Claude Sonnet', organization: 'Anthropic', brand: { key: 'anthropic', pngData: 'iVBORw0KGgo=' } }).logo, 'data:image/png;base64,iVBORw0KGgo=')
})

test('MiMo and GLM use shared provider images in both themes', () => {
  for (const [name, organization, key] of [
    ['MiMo-V2.6-Pro', 'Xiaomi', 'xiaomi'], ['mimo-v2.6-flash', 'Xiaomi', 'xiaomi'],
    ['GLM-5.3 (Max)', 'Z AI', 'zai'], ['glm-5.3-max', 'Z.ai', 'zai'], ['GLM-Image', 'Z AI', 'zai'],
    ['Opencode - GLM-5.3', undefined, 'zai'],
  ]) {
    const model = entry(1, name, 99, organization, { brand: { key, pngData: 'iVBORw0KGgo=' } })
    assert.equal(rowView(model).logo, 'data:image/png;base64,iVBORw0KGgo=', name)
    assert.equal(rowView(model, { dark: true }).logo, 'data:image/png;base64,iVBORw0KGgo=', name)
  }
})

test('provider rows use shared images or initials, with no packaged supplier PNGs', () => {
  for (const key of Object.keys(brandCatalog.colors).filter(key => key !== 'github')) {
    assert.equal(existsSync(new URL(`../../../assets/logos/${key}.png`, import.meta.url)), false, key)
    const model = entry(1, 'Provider model', 99, key, { brand: { key } })
    assert.equal(rowView(model).logo, '', key)
    assert.equal(rowView(model, { company: true }).logo, '', key)
    const ready = { ...model, brand: { key, pngData: 'iVBORw0KGgo=' } }
    assert.equal(rowView(ready).logo, 'data:image/png;base64,iVBORw0KGgo=', key)
    assert.equal(rowView(ready, { company: true }).logo, 'data:image/png;base64,iVBORw0KGgo=', key)
  }
  assert.equal(rowView(entry(1, 'Unknown model', 1, 'Unverified')).logo, '')
  const serverOnly = entry(1, 'K2 Horizon', 99, 'Institute of Foundation Models', {
    brand: { key: 'instituteoffoundationmodels', status: 'ready', pngData: 'iVBORw0KGgo=' },
  })
  assert.equal(rowView(serverOnly).logo, 'data:image/png;base64,iVBORw0KGgo=')
})

test('company images survive cached metadata; pending or missing images show initials', () => {
  const formerCompanyKeys = ["arceeai", "primeintellect", "01ai", "nexusflow", "ai21labs", "reka", "princetonnlp", "huggingface", "databricks", "shanghaiailaboratory", "snowflake", "lmsys", "ucberkeley", "nousresearch", "mosaicml", "technologyinnovationinstitute", "universityofwashington", "togetherai", "stanford", "nomicai", "laion", "stabilityai", "kuaishou"]
  for (const key of formerCompanyKeys) {
    assert.equal(existsSync(new URL(`../../../assets/logos/${key}.png`, import.meta.url)), false, key)
    for (const status of ['pending', 'missing', undefined]) {
      const fields = status ? { organizationBrand: { key, status } } : {}
      const rows = visibleRows(board([entry(1, 'Provider model', 99, key, fields)]), { grouping: 'company' })
      assert.equal(rows[0].logo, '', `${key}: ${status}`)
      assert.ok(rows[0].initial, key)
      assert.equal(rows[0].score, 99)
    }
    const cached = JSON.parse(JSON.stringify(board([entry(1, 'Provider model', 99, key, {
      organizationBrand: { key, status: 'ready', pngData: 'iVBORw0KGgo=' },
    })])))
    assert.equal(visibleRows(cached, { grouping: 'company' })[0].logo, 'data:image/png;base64,iVBORw0KGgo=', key)
  }
  const trinity = visibleRows(board([entry(1, 'trinity-large-thinking', 99, null)]), { grouping: 'company' })
  assert.equal(trinity[0].logo, '')
  const ready = visibleRows(board([
    entry(1, 'Best', 99, 'OpenAI', { organizationBrand: { key: 'openai', status: 'pending' } }),
    entry(2, 'Other', 90, 'Open AI', { brand: { key: 'openai', pngData: 'iVBORw0KGgo=' } }),
  ]), { grouping: 'company' })
  assert.equal(ready[0].logo, 'data:image/png;base64,iVBORw0KGgo=')
})

test('model and manufacturer images come from the shared snapshot without local substitution', () => {
  const model = entry(1, 'Wan 3', 99, 'Alibaba', { brand: { key: 'qwen' } })
  assert.equal(rowView(model).logo, '')
  const wan = brandCatalog.modelLogos.find(model => model.key === 'wan')
  const shared = { ...model, brand: { key: 'model-wan', pngData: wan.pngData },
    organizationBrand: { key: 'qwen', pngData: 'iVBORw0KGgo=' } }
  assert.equal(rowView(shared).logo, `data:image/png;base64,${wan.pngData}`)
  assert.equal(rowView(shared, { company: true }).logo, 'data:image/png;base64,iVBORw0KGgo=')
  assert.equal(rowView(entry(1, 'Claude Sonnet', 99, 'Anthropic')).logo, '')
  assert.equal(rowView(entry(1, 'Agent - GLM-5.3', 99, 'Unverified Harness')).logo, '')
  assert.equal(rowView(entry(1, 'Agent - GLM-5.3', 99, 'Unverified Harness'), { company: true }).logo, '')
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

test('timestamp dates use calendar days through three days ago, then the existing date format', () => {
  const fixture = JSON.parse(readFileSync(new URL('../../../Tests/fixtures/calendar-timestamps.json', import.meta.url), 'utf8'))
  const originalZone = process.env.TZ
  try {
    for (const sample of fixture.cases) {
      process.env.TZ = sample.timeZone
      // Mini-program Arena headers have always omitted the year.
      if (sample.includesYear) continue
      for (const language of ['en', 'zh-CN', 'zh-TW']) {
        assert.equal(formatTime(sample.date, language, new Date(sample.now), { dateOnly: sample.dateOnly, utc: sample.dateOnly }),
          language === 'en' ? sample.en : sample.zh, `${sample.name}, ${language}`)
      }
    }
  } finally {
    if (originalZone === undefined) delete process.env.TZ
    else process.env.TZ = originalZone
  }
})

test('rank movement labels use arrows, localize new entries and use company positions', () => {
  for (const language of ['en', 'zh-CN', 'zh-TW']) {
    const base = { rank: 2, name: 'Model', score: 99, organization: 'OpenAI' }
    for (const [change, expected, tone] of [[undefined, ''], [{delta:0}, ''], [{delta:3}, '↑3', 'up'], [{delta:-12}, '↓12', 'down'], [{isNew:true}, language === 'en' ? 'New' : '新', 'new']]) {
      const row = rowView({ ...base, rankChange: change }, { language })
      assert.equal(row.rankChangeText, expected)
      assert.equal(row.rankChangeTone, tone)
      assert.equal(row.rank, base.rank)
      assert.equal(row.medal, '🥈')
    }
    const snapshot = { kind: 'arenaText', entries: [{ ...base, rankChange: {delta:3}, companyRankChange:{delta:-1} }] }
    assert.equal(visibleRows(snapshot, { grouping:'company', language })[0].rankChangeText, '↓1')
    assert.equal(visibleRows(snapshot, { query:'Model', language })[0].rankChangeText, '↑3')
  }
})

test('公司榜不把旧模型图标当成公司图标，并优先使用其他型号的公司图', () => {
  const product = brandCatalog.providerLogos.qwen.pngData
  const model = entry(1, 'Qwen3.5', 99, 'Alibaba', { brand: { key: 'qwen', pngData: product }, organizationBrand: { key: 'qwen', pngData: product } })
  assert.equal(visibleRows(board([model]), { grouping: 'company' })[0].logo, '')
  const sibling = entry(2, 'Other', 90, 'Alibaba', { organizationBrand: { key: 'qwen', pngData: 'iVBORw0KGgo=' } })
  assert.equal(visibleRows(board([model, sibling]), { grouping: 'company' })[0].logo, 'data:image/png;base64,iVBORw0KGgo=')
  const legacy = entry(1, 'Qwen3.5', 99, 'Alibaba', { brand: { key: 'qwen', pngData: product } })
  assert.equal(visibleRows(board([legacy]), { grouping: 'company' })[0].logo, '')
})
