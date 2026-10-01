import assert from 'node:assert/strict'
import { mkdtempSync, readFileSync, rmSync } from 'node:fs'
import { spawnSync } from 'node:child_process'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { fileURLToPath } from 'node:url'
import test from 'node:test'
import { ipadProject } from './ipad-project.mjs'
import { ipadBuildPlan, ipadSimulator } from './ipad-build.mjs'

const uuid = '00000000-0000-0000-0000-000000000001'
test('generated iPad icon is opaque, 1024px and carries no private PNG metadata', { skip: process.platform !== 'darwin' }, (t) => {
  const directory = mkdtempSync(join(tmpdir(), 'ipad-icon-metadata-'))
  t.after(() => rmSync(directory, { recursive: true, force: true }))
  const output = join(directory, 'icon.png')
  const result = spawnSync('swift', [fileURLToPath(new URL('./ipad-icon.swift', import.meta.url)), output], { encoding: 'utf8', timeout: 60_000 })
  assert.equal(result.status, 0, result.stderr)
  const png = readFileSync(output)
  assert.equal(png.subarray(0, 8).toString('hex'), '89504e470d0a1a0a')
  const chunks = []
  for (let offset = 8; offset < png.length;) {
    const size = png.readUInt32BE(offset)
    assert.ok(offset + size + 12 <= png.length)
    chunks.push(png.toString('ascii', offset + 4, offset + 8))
    offset += size + 12
  }
  assert.equal(chunks[0], 'IHDR')
  assert.equal(chunks.at(-1), 'IEND')
  assert.ok(chunks.includes('IDAT'))
  assert.ok(chunks.every(chunk => ['IHDR', 'sRGB', 'IDAT', 'IEND'].includes(chunk)))
  assert.equal(png.readUInt32BE(16), 1024)
  assert.equal(png.readUInt32BE(20), 1024)
  assert.equal(png[25], 2) // RGB without an alpha channel.
  const inspected = spawnSync('swift', ['-e', `
    import AppKit
    import Foundation
    let image = NSBitmapImageRep(data: try! Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments.last!)))!
    let pixels = [(50, 50), (280, 700), (505, 700), (730, 700)].map { x, y -> [Double] in
      let color = image.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
      return [color.redComponent, color.greenComponent, color.blueComponent, color.alphaComponent].map { Double($0) }
    }
    print(String(data: try! JSONSerialization.data(withJSONObject: pixels), encoding: .utf8)!)
  `, output], { encoding: 'utf8', timeout: 60_000 })
  assert.equal(inspected.status, 0, inspected.stderr)
  const [background, cyan, green, purple] = JSON.parse(inspected.stdout)
  assert.ok(background.slice(0, 3).every(value => value > 0 && value < 0.3))
  assert.ok(cyan[1] > cyan[0] && cyan[2] > cyan[0])
  assert.ok(green[1] > green[0] && green[1] > green[2])
  assert.ok(purple[0] > purple[1] && purple[2] > purple[1])
  for (const pixel of [background, cyan, green, purple]) assert.equal(pixel[3], 1)
})
test('iPad checks build both Release SDKs and run deterministic simulator UI tests', () => {
  const plan = ipadBuildPlan('check', { device: uuid, phone: '00000000-0000-0000-0000-000000000002', directory: '/repo' })
  assert.equal(plan.length, 4)
  assert.ok(plan[0].includes('generic/platform=iOS Simulator'))
  assert.ok(plan[1].includes('generic/platform=iOS'))
  assert.ok(plan[2].includes(`platform=iOS Simulator,id=${uuid}`))
  assert.equal(plan[2].at(-1), 'test')
  assert.ok(plan[3].includes('platform=iOS Simulator,id=00000000-0000-0000-0000-000000000002'))
  assert.notEqual(plan[2][plan[2].indexOf('-resultBundlePath') + 1], plan[3][plan[3].indexOf('-resultBundlePath') + 1])
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
  assert.equal(ipadSimulator({ devices: { 'com.apple.CoreSimulator.SimRuntime.iOS-26-0': [{ name: 'iPhone 16', isAvailable: true, udid: uuid }] } }, 'iPhone'), uuid)
  assert.throws(() => ipadSimulator({ devices: {} }, 'iPhone'), /iPhone simulator/)
  assert.throws(() => ipadSimulator({ devices: {} }), /iPad simulator/)
})
test('iPad project uses only the portable UI library, shared version, and Debug-only fixtures', () => {
  const { project, scheme } = ipadProject({ version: '0.1.2', buildNumber: '17' })
  assert.equal(project, ipadProject({ version: '0.1.2', buildNumber: '17' }).project)
  assert.ok(project.includes('MARKETING_VERSION = "0.1.2"'))
  assert.ok(project.includes('CURRENT_PROJECT_VERSION = "17"'))
  assert.ok(project.includes('TARGETED_DEVICE_FAMILY = "1,2"'))
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
  assert.ok(ui.includes('Text("AI BenchGauge")'))
  assert.ok(!ui.includes('获取于'))
  assert.ok(!ui.includes('"Fetched"'))
  const { project } = ipadProject({ version: '0.1.2' })
  assert.ok(project.includes('path = ../../assets/logos'))
})

test('SDK build and family-specific UI checks are independently runnable', () => {
  assert.equal(ipadBuildPlan('build', { directory: '/repo' }).length, 2)
  for (const family of ['iPhone', 'iPad']) {
    const plan = ipadBuildPlan('test', { device: uuid, phone: uuid, family })
    assert.equal(plan.length, 1)
    assert.ok(plan[0].some(arg => arg.endsWith('.xcresult') && arg.includes(family)))
  }
  assert.equal(ipadBuildPlan('test', { device: uuid, family: 'iPad' }).length, 1)
  assert.throws(() => ipadBuildPlan('test', { device: uuid, family: 'iPhone' }), /simulator IDs/)
  assert.throws(() => ipadBuildPlan('test', { device: uuid, phone: uuid, family: 'unsupported' }), /family/)
})
