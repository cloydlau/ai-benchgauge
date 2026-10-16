import assert from 'node:assert/strict'
import test from 'node:test'
import { execFileSync } from 'node:child_process'
import { mkdtempSync, mkdirSync, writeFileSync, rmSync, symlinkSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { dirname, join } from 'node:path'
import { pathToFileURL } from 'node:url'
import { engineeringInvestment } from '../scripts/engineering-investment.mjs'
import { investmentContent } from '../src/core/investment.js'

function repository(t) {
  const root = mkdtempSync(join(tmpdir(), 'benchgauge-investment-'))
  t.after(() => rmSync(root, { recursive: true, force: true }))
  const git = (...args) => execFileSync('git', args, { cwd: root, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] })
  git('init', '-q')
  git('config', 'user.name', 'Investment test')
  git('config', 'user.email', 'investment@example.invalid')
  const write = (path, contents) => {
    mkdirSync(dirname(join(root, path)), { recursive: true })
    writeFileSync(join(root, path), contents)
  }
  return { root, git, write }
}

test('engineering totals use full history and tracked product text, excluding dependencies, generated files, binaries and local files', t => {
  const { root, git, write } = repository(t)
  write('Sources/main.swift', 'first\nsecond\n')
  write('apps/weapp/src/page.js', 'one\ntwo')
  write('fc/service.mjs', 'first\r\n\r\nthird\r\n')
  write('apps/weapp/empty.js', '')
  write('apps/weapp/image.png', Buffer.from([0, 1, 2]))
  write('apps/weapp/invalid.dat', Buffer.from([255, 254, 10]))
  write('apps/weapp/generated/stats.js', 'generated\n')
  write('apps/weapp/dist/app.js', 'built\n')
  write('apps/weapp/node_modules/dep.js', 'dependency\n')
  write('apps/windows/bin/app.txt', 'built\n')
  write('apps/windows/obj/app.txt', 'built\n')
  write('apps/weapp/package-lock.json', '{}\n')
  write('apps/weapp/ignored.js', 'previously tracked\n')
  write('docs/notes.md', 'not product code\n')
  symlinkSync(join(root, 'Sources/main.swift'), join(root, 'apps/link.swift'))
  git('add', '.')
  git('commit', '-qm', 'first')
  write('.gitignore', 'apps/weapp/ignored.js\n')
  git('add', '.gitignore')
  git('commit', '-qm', 'second')
  write('apps/weapp/local.js', 'untracked\n')
  assert.deepEqual(engineeringInvestment(root), { commitCount: 2, codeLineCount: 7 })
  write('Sources/main.swift', 'current\n')
  rmSync(join(root, 'fc/service.mjs'))
  assert.deepEqual(engineeringInvestment(root), { commitCount: 2, codeLineCount: 3 })
  // A stage inside the checkout must not accidentally count its parent repository.
  mkdirSync(join(root, 'work/stage'), { recursive: true })
  assert.throws(() => engineeringInvestment(join(root, 'work/stage')), /repository root/)
})

test('a shallow checkout cannot publish a misleading commit count', t => {
  const { root, git, write } = repository(t)
  write('Sources/main.swift', 'code\n')
  git('add', '.')
  git('commit', '-qm', 'first')
  git('commit', '--allow-empty', '-qm', 'second')
  const shallow = join(root, 'shallow')
  git('clone', '--depth', '1', pathToFileURL(root).href, shallow)
  assert.throws(() => engineeringInvestment(shallow), /full Git history/)
})

test('investment content localizes counters, annual budget estimates and excluded expenses', () => {
  for (const [language, title, commits, note] of [
    ['en', 'Costs and investment', 'Commits', /not yet included/],
    ['zh-CN', '成本与投入', '提交次数', /暂未计入/],
    ['zh-TW', '成本與投入', '提交次數', /暫未計入/],
  ]) {
    const content = investmentContent({ commitCount: 1234, codeLineCount: 56789 }, language)
    assert.equal(content.title, title)
    assert.deepEqual(content.metrics.map(metric => metric.value), ['1,234', '56,789'])
    assert.equal(content.metrics[0].label, commits)
    assert.match(content.costNote, note)
    assert.equal(content.groups.length, 3)
    assert.equal(content.total, 26500)
    assert.ok(content.totalText.endsWith('¥26,500'))
  }
})

test('annual budgets include only applicable Watrek items and never turn unknown expenses into free services', () => {
  const content = investmentContent({ commitCount: 10, codeLineCount: 100 }, 'zh-CN')
  const items = content.groups.flatMap(group => group.items)
  assert.deepEqual(items.map(item => item.id), ['server', 'storage', 'logs', 'weapp', 'tokens', 'staff', 'data', 'operations'])
  assert.deepEqual(content.groups.map(group => group.amount), [2200, 300, 24000])
  assert.equal(items.find(item => item.id === 'tokens').amount, 2000 * 12)
  assert.deepEqual(items.filter(item => item.amount === null).map(item => item.amountText), ['暂未核算', '暂未核算', '暂未核算'])
  assert.equal(content.total, items.reduce((sum, item) => sum + (item.amount ?? 0), 0))
  assert.match(content.budgetIntro, /年度预算/)
  assert.match(content.budgetIntro, /非实际账单/)
  assert.match(content.costNote, /人力、数据维护、运营/)
})
