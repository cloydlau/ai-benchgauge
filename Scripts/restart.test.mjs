import assert from 'node:assert/strict'
import { spawnSync } from 'node:child_process'
import { copyFileSync, existsSync, mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { dirname, join } from 'node:path'
import test from 'node:test'
import { fileURLToPath } from 'node:url'

for (const scenario of ['old-location', 'stopped', 'inspection-failed']) {
  test(`restart identifies the application across checkout moves: ${scenario}`, (t) => {
    const root = realpathSync(mkdtempSync(join(tmpdir(), 'benchgauge-restart-')))
    t.after(() => rmSync(root, { recursive: true, force: true }))
    mkdirSync(join(root, 'Scripts'))
    mkdirSync(join(root, 'bin'))
    copyFileSync(join(dirname(fileURLToPath(import.meta.url)), 'restart.sh'), join(root, 'Scripts/restart.sh'))
    const executable = (name, code) => writeFileSync(join(root, 'bin', name), `#!/bin/sh\n${code}\n`, { mode: 0o755 })
    executable('pgrep', scenario === 'inspection-failed' ? 'exit 2' : `
      printf '%s' "$2" > queried-pattern
      if test -f launched; then echo 789; exit 0; fi
      if test '${scenario}' = old-location && ! test -f stopped; then echo 123; exit 0; fi
      exit 1
    `)
    executable('pkill', 'printf "%s" "$2" > killed-pattern; touch stopped')
    executable('open', 'printf "%s" "$1" > opened-app; touch launched')
    executable('sleep', 'exit 0')
    const result = spawnSync('zsh', [join(root, 'Scripts/restart.sh')], { cwd: root, env: { ...process.env, DESKTOP_NOTIFY: '0', PATH: join(root, 'bin') + ':' + process.env.PATH }, encoding: 'utf8' })
    if (scenario === 'inspection-failed') {
      assert.equal(result.status, 2, result.stderr)
      assert.equal(existsSync(join(root, 'opened-app')), false)
      return
    }
    assert.equal(result.status, 0, result.stderr)
    assert.equal(readFileSync(join(root, 'opened-app'), 'utf8'), join(root, 'outputs/AI-BenchGauge.app'))
    const pattern = readFileSync(join(root, 'queried-pattern'), 'utf8')
    assert.match('/previous/checkout/outputs/AI-BenchGauge.app/Contents/MacOS/leaderboard-menu', new RegExp(pattern))
    assert.doesNotMatch('/previous/checkout/outputs/Other.app/Contents/MacOS/leaderboard-menu', new RegExp(pattern))
    assert.doesNotMatch('/previous/checkout/outputs/AI-BenchGauge.app/Contents/MacOS/leaderboard-menu-helper', new RegExp(pattern))
    if (scenario === 'old-location') assert.equal(readFileSync(join(root, 'killed-pattern'), 'utf8'), pattern)
    else assert.equal(existsSync(join(root, 'killed-pattern')), false)
  })
}
