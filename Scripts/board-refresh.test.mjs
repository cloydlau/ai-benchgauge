import assert from 'node:assert/strict'
import test from 'node:test'
import { readFileSync } from 'node:fs'

const read = path => readFileSync(new URL(`../${path}`, import.meta.url), 'utf8')

test('the macOS periodic account tick cannot refresh rankings or schedule a leaderboard retry', () => {
  const source = read('apps/macos/Sources/AppState.swift')
  const tick = source.slice(source.indexOf('private func tick()'), source.indexOf('\n    private func ', source.indexOf('private func tick()') + 1))
  assert.ok(tick.includes('refreshQuotas('), 'Account quota monitoring remains active')
  assert.doesNotMatch(tick, /refreshNow|isFresh|schedule\./)
  assert.doesNotMatch(source, /UpdateSchedule|refreshPending/)
})

test('Windows timers cannot refresh rankings; entry checks and explicit refresh use different engine commands', () => {
  const source = read('apps/windows/BenchGauge/MainWindow.cs')
  for (const timer of source.matchAll(/\w+\.Tick \+=([\s\S]*?)(?=\n        \w+\.Tick|\n        Closed|\n        Activated)/g)) {
    assert.doesNotMatch(timer[1], /refreshBoards/)
  }
  assert.ok(source.includes('Refresh("refreshBoardsIfStale"), Refresh("refreshQuotas")'))
  assert.doesNotMatch(source, /engine\.Request\("cachedBoards"/)
  const controls = read('apps/windows/BenchGauge/MainWindow.Appearance.cs')
  assert.match(controls, /prefs\.Category = value;[^\n]*Refresh\("refreshBoardsIfStale"\)/)
  assert.match(controls, /freshness\.MouseLeftButtonUp[^\n]*Refresh\("refreshBoards"\)/)
})

test('iOS binds automatic checks to the selected source and keeps per-board manual refresh', () => {
  const source = read('apps/ios/UI/LeaderboardPadView.swift')
  assert.match(source, /\.task\(id: store\.selectedKind\) \{ await store\.refresh\(\) \}/)
  const foreground = source.slice(source.indexOf('.onChange(of: scenePhase)'), source.indexOf('\n    }', source.indexOf('.onChange(of: scenePhase)')))
  assert.doesNotMatch(foreground, /store\.refresh/)
  assert.match(source, /\.refreshable \{ await store\.refresh\(kind: kind, force: true\) \}/)
})
