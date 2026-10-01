import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'
import { ipadProject } from './ipad-project.mjs'
import { ipadBuildPlan, ipadSimulator } from './ipad-build.mjs'

const uuid = '00000000-0000-0000-0000-000000000001'
test('iPad checks build both Release SDKs and run deterministic simulator UI tests', () => {
  const plan = ipadBuildPlan('check', { device: uuid, directory: '/repo' })
  assert.equal(plan.length, 3)
  assert.ok(plan[0].includes('generic/platform=iOS Simulator'))
  assert.ok(plan[1].includes('generic/platform=iOS'))
  assert.ok(plan[2].includes(`platform=iOS Simulator,id=${uuid}`))
  assert.equal(plan[2].at(-1), 'test')
  for (const args of plan) assert.ok(args.includes('CODE_SIGNING_ALLOWED=NO'))
  assert.throws(() => ipadBuildPlan('archive'), /APPLE_TEAM_ID/)
  const archive = ipadBuildPlan('archive', { team: 'ABCDEFGHIJ' })[0]
  assert.equal(archive.at(-1), 'archive')
  assert.ok(!archive.includes('CODE_SIGNING_ALLOWED=NO'))
})
test('simulator selection excludes iPhones, old runtimes and unavailable iPads', () => {
  assert.equal(ipadSimulator({ devices: {
    'com.apple.CoreSimulator.SimRuntime.iOS-16-0': [{ name: 'iPad', isAvailable: true, udid: uuid }],
    'com.apple.CoreSimulator.SimRuntime.iOS-26-0': [
      { name: 'iPhone', isAvailable: true, udid: uuid },
      { name: 'iPad Air', isAvailable: false, udid: uuid },
      { name: 'iPad Pro', isAvailable: true, udid: uuid },
    ],
  } }), uuid)
  assert.throws(() => ipadSimulator({ devices: {} }), /iPad simulator/)
})
test('iPad project uses only the portable UI library, shared version, and Debug-only fixtures', () => {
  const { project, scheme } = ipadProject({ version: '0.1.2', buildNumber: '17' })
  assert.equal(project, ipadProject({ version: '0.1.2', buildNumber: '17' }).project)
  assert.ok(project.includes('MARKETING_VERSION = "0.1.2"'))
  assert.ok(project.includes('CURRENT_PROJECT_VERSION = "17"'))
  assert.ok(project.includes('TARGETED_DEVICE_FAMILY = "2"'))
  assert.ok(project.includes('IPHONEOS_DEPLOYMENT_TARGET = "17.0"'))
  assert.ok(project.includes('ONLY_ACTIVE_ARCH = "YES"'))
  assert.ok(project.includes('ONLY_ACTIVE_ARCH = "NO"'))
  assert.ok(project.includes('productName = LeaderboardPadUI'))
  assert.ok(!project.includes('productName = LeaderboardCore'))
  assert.ok(!project.includes('Sparkle'))
  assert.ok(scheme.includes('BenchGaugeUITests'))
  assert.ok(readFileSync(new URL('../apps/ipad/App/DebugFixtures.swift', import.meta.url), 'utf8').startsWith('#if DEBUG'))
  assert.equal(readFileSync(new URL('../apps/ipad/UI/Resources/AI-BenchGauge.txt', import.meta.url), 'utf8'), readFileSync(new URL('../LICENSE', import.meta.url), 'utf8'))
  assert.throws(() => ipadProject({ version: 'v1.0.0' }), /version/)
})
test('iPad uses one full-screen scene with rotation and respects newer system windowing', () => {
  const info = readFileSync(new URL('../apps/ipad/App/Info.plist', import.meta.url), 'utf8')
  for (const orientation of ['Portrait', 'PortraitUpsideDown', 'LandscapeLeft', 'LandscapeRight']) {
    assert.ok(info.includes(`UIInterfaceOrientation${orientation}`))
  }
  assert.match(info, /<key>UIRequiresFullScreen<\/key>\s*<true\/>/)
  assert.match(info, /<key>UIRequiresFullScreenIgnoredStartingWithVersion<\/key>\s*<string>26<\/string>/)
  assert.match(info, /<key>UIApplicationSupportsMultipleScenes<\/key>\s*<false\/>/)
  assert.ok(!info.includes('NSAppTransportSecurity'))
})

test('iPad source names and explanations stay aligned with desktop copy', () => {
  const desktop = readFileSync(new URL('../apps/macos/Sources/LeaderboardView.swift', import.meta.url), 'utf8')
  const presentation = readFileSync(new URL('../Sources/LeaderboardKit/LeaderboardPresentation.swift', import.meta.url), 'utf8')
  const desktopLenses = desktop.slice(desktop.indexOf('private extension LeaderboardCategory'), desktop.indexOf('private struct SourceLensDescription'))
  const titles = [...desktopLenses.matchAll(/case \.\w+: "([^"]+)"/g)].map(match => match[1])
  assert.equal(titles.length, 8)
  for (const title of titles) assert.ok(presentation.includes(JSON.stringify(title)), `iPad source title differs: ${title}`)
  const copyPairs = [...desktopLenses.matchAll(/language\.text\(\s*"([^"]+)",\s*"([^"]+)"/g)]
  assert.equal(copyPairs.length, 16)
  for (const [, english, chinese] of copyPairs) {
    assert.ok(presentation.includes(JSON.stringify(english)), `Missing desktop copy: ${english}`)
    assert.ok(presentation.includes(JSON.stringify(chinese)), `Missing desktop copy: ${chinese}`)
  }
  const ui = readFileSync(new URL('../apps/ipad/UI/LeaderboardPadView.swift', import.meta.url), 'utf8')
  assert.ok(ui.includes('Text(tr("AI BenchGauge", "智衡"))'))
  assert.ok(!ui.includes('获取于'))
  assert.ok(!ui.includes('"Fetched"'))
  const { project } = ipadProject({ version: '0.1.2' })
  assert.ok(project.includes('path = ../../assets/logos'))
})
