import assert from 'node:assert/strict'
import { spawnSync } from 'node:child_process'
import { copyFileSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import test from 'node:test'

const scripts = dirname(fileURLToPath(import.meta.url))
const repository = resolve(scripts, '..')

test('the repository entry binds its configuration when invoked from another cwd', () => {
  const result = spawnSync(process.execPath, [join(scripts, 'calmmit.mjs'), 'config'], {
    cwd: tmpdir(),
    env: process.env,
    encoding: 'utf8',
    timeout: 10000,
  })
  assert.equal(result.status, 0, result.stderr)
  const effective = JSON.parse(result.stdout)
  const configured = JSON.parse(readFileSync(join(repository, 'calmmit.config.json'), 'utf8'))
  assert.equal(effective.preset, 'swift')
  assert.deepEqual(effective.steps, configured.steps)
  assert.equal(effective.commit.push, false)
})

test('actual CI and commit adapters use the live library and honor disabled native tests', (t) => {
  const root = mkdtempSync(join(tmpdir(), 'benchgauge calmmit integration '))
  t.after(() => rmSync(root, { recursive: true, force: true }))
  mkdirSync(join(root, 'Scripts'))
  for (const file of ['calmmit.mjs', 'ci-checks.mjs', 'commit.mjs'])
    copyFileSync(join(scripts, file), join(root, 'Scripts', file))
  const configured = JSON.parse(readFileSync(join(repository, 'calmmit.config.json'), 'utf8'))
  const library = resolve(repository, process.env.CALMMIT_PATH || configured.library)
  writeFileSync(join(root, '.gitignore'), '.calmmit.log\n')
  writeFileSync(
    join(root, 'calmmit.config.json'),
    JSON.stringify({
      library,
      preset: 'custom',
      steps: { lint: true, tests: false, build: false },
      commands: {
        lint: ['node', '-e', 'process.stdout.write("fixture lint passed")'],
        tests: ['node', '-e', 'throw Error("disabled native tests executed")'],
      },
      identity: { allowConfiguredModel: false },
      commit: { review: true, generateMessage: false, split: false, push: false },
      repair: { enabled: false },
    }),
  )
  const env = {
    ...process.env,
    MODEL_NAME: 'fixture-model',
    DESKTOP_NOTIFY: '0',
    CALMMIT_PATH: library,
    GIT_CONFIG_GLOBAL: '/dev/null',
    GIT_CONFIG_NOSYSTEM: '1',
  }
  const run = (args) =>
    spawnSync(process.execPath, args, { cwd: root, env, encoding: 'utf8', timeout: 15000 })
  const checked = run(['Scripts/ci-checks.mjs'])
  assert.equal(checked.status, 0, checked.stdout + checked.stderr)
  assert.match(checked.stdout, /fixture lint passed/)
  assert.doesNotMatch(checked.stdout, /\[tests\]/)
  assert.equal(spawnSync('git', ['init', '-q'], { cwd: root, env }).status, 0)
  const committed = run(['Scripts/commit.mjs', '-m', 'feat: 添加接入测试'])
  assert.equal(committed.status, 0, committed.stdout + committed.stderr)
  const identity = spawnSync('git', ['log', '-1', '--format=%an|%cn'], {
    cwd: root,
    env,
    encoding: 'utf8',
  })
  assert.equal(identity.stdout.trim(), 'fixture-model|fixture-model')
  assert.doesNotMatch(committed.stdout, /\[tests\]/)
})

for (const [filename, nextStep] of [
  ['ci.yml', 'Screenshots and recordings need review'],
  ['release.yml', 'Validate shared app configuration'],
  ['windows-build.yml', 'Tests, runtime closure and native UI'],
]) {
  test(`${filename}: pinned shared source is fetched before consumers execute`, () => {
    const text = readFileSync(join(repository, '.github/workflows', filename), 'utf8')
    const guard = text.indexOf('name: Require shared CI source repository')
    const checkout = text.indexOf('repository: ${{ vars.CALMMIT_REPOSITORY }}')
    assert.ok(guard > 0 && checkout > guard && text.indexOf(`name: ${nextStep}`) > checkout)
    assert.match(text, /CALMMIT_PATH: \$\{\{ github.workspace \}\}\/\.calmmit-library/)
    assert.match(text, /ref: \$\{\{ vars.CALMMIT_SHA \}\}/)
    assert.match(text, /\[0-9a-f\]\{40\}/)
    assert.match(
      text.slice(checkout, text.indexOf('      - ', checkout)),
      /persist-credentials: false/,
    )
  })
}
