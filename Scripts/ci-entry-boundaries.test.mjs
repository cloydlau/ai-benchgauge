import test from 'node:test'
import assert from 'node:assert/strict'
import fs from 'node:fs'
import { spawnSync } from 'node:child_process'
import { realpathSync } from 'node:fs'
import { join } from 'node:path'
import { tmpdir } from 'node:os'

function fixture(t) {
  const root = realpathSync(fs.mkdtempSync(join(tmpdir(), 'benchgauge-ci-entry-')))
  t.after(() => fs.rmSync(root, { recursive: true, force: true }))
  fs.mkdirSync(join(root, 'Scripts'))
  fs.mkdirSync(join(root, 'work/test-results'), { recursive: true })
  return root
}

test('CI packaging preserves a current full test receipt and propagates packaging failures', t => {
  const root = fixture(t)
  fs.copyFileSync(new URL('./ci-build.mjs', import.meta.url), join(root, 'Scripts/ci-build.mjs'))
  fs.writeFileSync(join(root, 'Scripts/calmmit.mjs'), `export const ci={root:${JSON.stringify(root)},load:async()=>({loadConfig:()=>({steps:{tests:process.env.UNIT_TESTS!=='0'}})})}`)
  fs.writeFileSync(join(root, 'Scripts/test.mjs'), `export const testInputSignature = () => 'fixture-pass'`)
  fs.writeFileSync(join(root, 'hook.cjs'), `const cp=require('node:child_process'),fs=require('node:fs');cp.spawnSync=(command,args,options)=>{fs.writeFileSync(process.env.UNIT_RECORD,JSON.stringify({command,args,env:options.env}));return {status:process.env.UNIT_STATUS==='null'?null:Number(process.env.UNIT_STATUS),error:process.env.UNIT_ERROR?new Error('fixture packaging error'):null}};require('node:module').syncBuiltinESMExports()`)
  const record = join(root, 'record.json')
  const invoke = (env = {}) => spawnSync(process.execPath, ['--require', join(root, 'hook.cjs'), join(root, 'Scripts/ci-build.mjs')], { encoding: 'utf8', env: { ...process.env, UNIT_RECORD: record, UNIT_TESTS: '1', UNIT_STATUS: '0', UNIT_ERROR: '', BENCHGAUGE_SKIP_TESTS: '1', ...env } })
  fs.writeFileSync(join(root, 'work/test-results/latest.json'), JSON.stringify({ status: 0, signature: 'fixture-pass' }))
  assert.equal(invoke().status, 0)
  const passed = JSON.parse(fs.readFileSync(record)); assert.equal(passed.env.BENCHGAUGE_SKIP_TESTS, undefined); assert.equal(passed.env.BENCHGAUGE_TEST_PASS, 'fixture-pass')
  assert.equal(invoke({ UNIT_TESTS: '0' }).status, 0); assert.equal(JSON.parse(fs.readFileSync(record)).env.BENCHGAUGE_SKIP_TESTS, '1')
  fs.writeFileSync(join(root, 'work/test-results/latest.json'), JSON.stringify({ status: 0, signature: 'stale' }))
  assert.equal(invoke({ BENCHGAUGE_TEST_PASS: '' }).status, 0); assert.equal(JSON.parse(fs.readFileSync(record)).env.BENCHGAUGE_TEST_PASS, '')
  fs.writeFileSync(join(root, 'work/test-results/latest.json'), JSON.stringify({ status: 1, signature: 'fixture-pass' }))
  assert.equal(invoke().status, 0)
  fs.writeFileSync(join(root, 'work/test-results/latest.json'), 'invalid JSON')
  assert.equal(invoke().status, 0)
  assert.equal(invoke({ UNIT_STATUS: 'null' }).status, 1)
  assert.match(invoke({ UNIT_ERROR: '1' }).stderr, /fixture packaging error/)
})

test('business Calmmit bridge starts only an isolated client and describes a missing library', t => {
  const root = fixture(t)
  fs.copyFileSync(new URL('./calmmit.mjs', import.meta.url), join(root, 'Scripts/calmmit.mjs'))
  fs.mkdirSync(join(root, 'library/src'), { recursive: true })
  fs.writeFileSync(join(root, 'library/src/client.mjs'), `import {writeFileSync}from'node:fs';export const createClient=({root})=>({run:()=>writeFileSync(root+'/ran','fixture')})`)
  fs.writeFileSync(join(root, 'calmmit.config.json'), '{"library":"./library"}')
  const invoke = () => spawnSync(process.execPath, [join(root, 'Scripts/calmmit.mjs')], { encoding: 'utf8', env: { ...process.env, CALMMIT_PATH: '' } })
  assert.equal(invoke().status, 0)
  assert.equal(fs.readFileSync(join(root, 'ran'), 'utf8'), 'fixture')
  fs.writeFileSync(join(root, 'calmmit.config.json'), '{"library":"./missing"}')
  assert.match(invoke().stderr, /找不到 Calmmit/)
})
