import assert from 'node:assert/strict'
import test from 'node:test'
import { updateDependencies } from './dev-update-deps.mjs'

test('macOS updates Swift constraints; Windows updates both NuGet project graphs without invoking Swift', () => {
  for (const platform of ['darwin', 'win32']) {
    const calls = []
    assert.equal(
      updateDependencies({
        platform,
        log: () => {},
        execute: (command, args, options) => {
          calls.push([command, args])
          assert.equal(options.liveOutput, true)
          assert.ok(options.cwd.endsWith('ai-benchgauge'))
          return { status: 0 }
        },
      }),
      0,
    )
    if (platform === 'darwin') assert.deepEqual(calls, [['swift', ['package', 'update']]])
    else {
      assert.equal(calls.length, 2)
      assert.ok(
        calls.every(
          ([command, args]) =>
            command === 'dotnet' && args[0] === 'package' && args[1] === 'update',
        ),
      )
      assert.ok(calls.some(([, args]) => args.at(-1).includes('BenchGauge.Shared/')))
      assert.ok(calls.some(([, args]) => args.at(-1).includes('BenchGauge/')))
    }
  }
})

test('failed native update retains its error and stops before updating another project', () => {
  const messages = []
  let calls = 0
  const status = updateDependencies({
    platform: 'win32',
    log: (message) => messages.push(message),
    execute: () => {
      calls++
      return { status: 1, error: new Error('fixture SDK unavailable') }
    },
  })
  assert.equal(status, 1)
  assert.equal(calls, 1)
  assert.match(messages.at(-1), /fixture SDK unavailable/)
})
