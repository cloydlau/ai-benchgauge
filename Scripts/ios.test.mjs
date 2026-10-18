import assert from 'node:assert/strict'
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs'
import { spawnSync } from 'node:child_process'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { fileURLToPath } from 'node:url'
import test from 'node:test'
import { generateIOSProject, iosProject } from './ios-project.mjs'
import { iosBuildPlan, iosSimulator } from './ios-build.mjs'

const uuid = '00000000-0000-0000-0000-000000000001'
test('generated iPad icon is opaque, 1024px and carries no private PNG metadata', { skip: process.platform !== 'darwin' }, (t) => {
  const directory = mkdtempSync(join(tmpdir(), 'ipad-icon-metadata-'))
  t.after(() => rmSync(directory, { recursive: true, force: true }))
  const output = join(directory, 'icon.png')
  const result = spawnSync('swift', [fileURLToPath(new URL('./ios-icon.swift', import.meta.url)), output], { encoding: 'utf8', timeout: 60_000 })
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
  const design = JSON.parse(readFileSync(new URL('../assets/brand/design.json', import.meta.url), 'utf8'))
  const inspected = spawnSync('swift', ['-e', `
    import AppKit
    import Foundation
    let image = NSBitmapImageRep(data: try! Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments.last!)))!
    let pixels = [(50, 50), (280, 784), (336, 664), (512, 196)].map { x, y -> [Double] in
      let color = image.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
      return [color.redComponent, color.greenComponent, color.blueComponent, color.alphaComponent].map { Double($0) }
    }
    // PNG export converts AppKit's calibrated drawing colors to sRGB.
    let hex = UInt32(CommandLine.arguments[CommandLine.arguments.count - 2].dropFirst(), radix: 16)!
    let ink = NSColor(calibratedRed: CGFloat((hex >> 16) & 255) / 255,
        green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255,
        alpha: 1).usingColorSpace(.deviceRGB)!
    let expected = [ink.redComponent, ink.greenComponent, ink.blueComponent, ink.alphaComponent].map { Double($0) }
    print(String(data: try! JSONSerialization.data(withJSONObject: pixels + [expected]), encoding: .utf8)!)
  `, design.ink, output], { encoding: 'utf8', timeout: 60_000 })
  assert.equal(inspected.status, 0, inspected.stderr)
  const [background, node, connection, outputNode, ink] = JSON.parse(inspected.stdout)
  assert.ok(background.slice(0, 3).every(value => value > 0 && value < 0.3))
  assert.ok(node.slice(0, 3).every((value, index) => Math.abs(value - ink[index]) < 0.005))
  assert.ok(connection[2] > connection[0] && connection[1] > 0.5)
  assert.ok(outputNode[1] > outputNode[0] && outputNode[2] > outputNode[0])
  for (const pixel of [background, node, connection, outputNode]) assert.equal(pixel[3], 1)
})
test('iPad checks build both Release SDKs and run deterministic simulator UI tests', () => {
  const plan = iosBuildPlan('check', { device: uuid, phone: '00000000-0000-0000-0000-000000000002', directory: '/repo' })
  assert.equal(plan.length, 4)
  assert.ok(plan[0].includes('generic/platform=iOS Simulator'))
  assert.ok(plan[1].includes('generic/platform=iOS'))
  assert.ok(plan[2].includes(`platform=iOS Simulator,id=${uuid}`))
  assert.equal(plan[2].at(-1), 'test')
  assert.ok(plan[3].includes('platform=iOS Simulator,id=00000000-0000-0000-0000-000000000002'))
  assert.notEqual(plan[2][plan[2].indexOf('-resultBundlePath') + 1], plan[3][plan[3].indexOf('-resultBundlePath') + 1])
  for (const args of plan) assert.ok(args.includes('CODE_SIGNING_ALLOWED=NO'))
  assert.throws(() => iosBuildPlan('archive'), /APPLE_TEAM_ID/)
  const archive = iosBuildPlan('archive', { team: 'ABCDEFGHIJ' })[0]
  assert.equal(archive.at(-1), 'archive')
  assert.ok(!archive.includes('CODE_SIGNING_ALLOWED=NO'))
})
test('simulator selection excludes iPhones, old runtimes and unavailable iPads', () => {
  assert.equal(iosSimulator({ devices: {
    'com.apple.CoreSimulator.SimRuntime.iOS-16-0': [{ name: 'iPad', isAvailable: true, udid: uuid }],
    'com.apple.CoreSimulator.SimRuntime.iOS-26-0': [
      { name: 'iPhone', isAvailable: true, udid: uuid },
      { name: 'iPad Air', isAvailable: false, udid: uuid },
      { name: 'iPad Pro', isAvailable: true, udid: uuid },
    ],
  } }), uuid)
  assert.equal(iosSimulator({ devices: { 'com.apple.CoreSimulator.SimRuntime.iOS-26-0': [{ name: 'iPhone 16', isAvailable: true, udid: uuid }] } }, 'iPhone'), uuid)
  assert.throws(() => iosSimulator({ devices: {} }, 'iPhone'), /iPhone simulator/)
  assert.throws(() => iosSimulator({ devices: {} }), /iPad simulator/)
})
test('iPad project uses only the portable UI library, shared version, and Debug-only fixtures', () => {
  const { project, scheme } = iosProject({ version: '0.1.2', buildNumber: '17' })
  assert.equal(project, iosProject({ version: '0.1.2', buildNumber: '17' }).project)
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
  assert.ok(readFileSync(new URL('../apps/ios/App/DebugFixtures.swift', import.meta.url), 'utf8').startsWith('#if DEBUG'))
  assert.equal(readFileSync(new URL('../apps/ios/UI/Resources/AI-BenchGauge.txt', import.meta.url), 'utf8'), readFileSync(new URL('../LICENSE', import.meta.url), 'utf8'))
  assert.throws(() => iosProject({ version: 'v1.0.0' }), /version/)
})
test('iPad uses one full-screen scene with rotation and respects newer system windowing', () => {
  const info = readFileSync(new URL('../apps/ios/App/Info.plist', import.meta.url), 'utf8')
  for (const orientation of ['Portrait', 'PortraitUpsideDown', 'LandscapeLeft', 'LandscapeRight']) {
    assert.ok(info.includes(`UIInterfaceOrientation${orientation}`))
  }
  assert.match(info, /<key>UIRequiresFullScreen<\/key>\s*<true\/>/)
  assert.match(info, /<key>UIRequiresFullScreenIgnoredStartingWithVersion<\/key>\s*<string>26<\/string>/)
  assert.match(info, /<key>UIApplicationSupportsMultipleScenes<\/key>\s*<false\/>/)
  assert.ok(!info.includes('NSAppTransportSecurity'))
})

test('App Store distribution uses the configured Apple ID and permits an unpublished app', (t) => {
  const directory = mkdtempSync(join(tmpdir(), 'benchgauge-store-project-'))
  t.after(() => rmSync(directory, { recursive: true, force: true }))
  mkdirSync(join(directory, 'config'), { recursive: true })
  for (const appStoreID of [null, '1234567890']) {
    writeFileSync(join(directory, 'config/app.json'), JSON.stringify({ version: '0.1.2', appStoreID }))
    const path = generateIOSProject(directory, { engineeringStats: { commitCount: 12, codeLineCount: 345 } })
    const project = readFileSync(join(path, 'project.pbxproj'), 'utf8')
    assert.ok(project.includes(`BENCHGAUGE_APP_STORE_ID = "${appStoreID ?? ''}"`))
  }
  for (const appStoreID of ['', '0', '00123', 123, 'https://github.com/example', '123;OTHER=YES']) {
    assert.throws(() => iosProject({ version: '0.1.2', appStoreID }), /App Store ID/)
  }
})

test('iPhone, iPad and desktop source copy uses the shared presentation rules', () => {
  const desktop = readFileSync(new URL('../apps/macos/Sources/LeaderboardView.swift', import.meta.url), 'utf8')
  const desktopLenses = desktop.slice(desktop.indexOf('private extension LeaderboardCategory'), desktop.indexOf('private struct SourceLensDescription'))
  assert.ok(desktopLenses.includes('LeaderboardPresentation.title(leftKind'))
  assert.ok(desktopLenses.includes('LeaderboardPresentation.title(rightKind'))
  assert.ok(desktopLenses.includes('LeaderboardPresentation.explanation(kind'))
  assert.ok(!desktopLenses.includes('language.text('))
  const ui = readFileSync(new URL('../apps/ios/UI/LeaderboardPadView.swift', import.meta.url), 'utf8')
  for (const method of ['title', 'sourceSummary', 'sourceHelp']) {
    assert.ok(desktop.includes(`LeaderboardPresentation.${method}(`))
    assert.ok(ui.includes(`LeaderboardPresentation.${method}(`))
  }
  assert.ok(ui.includes('store.language.appName'))
  assert.ok(!ui.includes('获取于'))
  assert.ok(!ui.includes('"Fetched"'))
  const { project } = iosProject({ version: '0.1.2' })
  assert.ok(project.includes('path = "../../assets/logos"'))
})

test('SDK build and family-specific UI checks are independently runnable', () => {
  assert.equal(iosBuildPlan('build', { directory: '/repo' }).length, 2)
  for (const family of ['iPhone', 'iPad']) {
    const plan = iosBuildPlan('test', { device: uuid, phone: uuid, family })
    assert.equal(plan.length, 1)
    assert.ok(plan[0].some(arg => arg.endsWith('.xcresult') && arg.includes(family)))
  }
  assert.equal(iosBuildPlan('test', { device: uuid, family: 'iPad' }).length, 1)
  assert.throws(() => iosBuildPlan('test', { device: uuid, family: 'iPhone' }), /simulator IDs/)
  assert.throws(() => iosBuildPlan('test', { device: uuid, phone: uuid, family: 'unsupported' }), /family/)
})

 test('local deployment generates a separate project referencing real sources without replacing the opened Xcode project', (t) => {
  const directory = mkdtempSync(join(tmpdir(), 'benchgauge-ios-project-'))
  t.after(() => rmSync(directory, { recursive: true, force: true }))
  mkdirSync(join(directory, 'config'), { recursive: true })
  writeFileSync(join(directory, 'config/app.json'), '{"version":"0.1.2"}')
  const original = join(directory, 'apps/ios/AI-BenchGauge.xcodeproj')
  mkdirSync(original, { recursive: true }); writeFileSync(join(original, 'project.pbxproj'), 'personal Xcode settings')
  const generated = generateIOSProject(directory, { projectDirectory: join(directory, 'work/ios-deploy/Project'),
    engineeringStats: { commitCount: 12, codeLineCount: 345 },
    sourceDirectory: join(directory, 'apps/ios'), packageDirectory: directory, logoDirectory: join(directory, 'assets/logos'),
    assetDirectory: join(directory, 'work/ios-deploy/Assets.xcassets'), team: 'ABCDEFGHIJ' })
  const project = readFileSync(join(generated, 'project.pbxproj'), 'utf8')
  for (const source of ['App/BenchGaugeApp.swift', 'App/DebugFixtures.swift', 'App/PrivacyInfo.xcprivacy', 'App/Info.plist']) {
    assert.ok(project.includes(join(directory, 'apps/ios', source)))
  }
  assert.ok(project.includes(`relativePath = "${directory}"`))
  assert.ok(project.includes(join(directory, 'work/ios-deploy/Assets.xcassets')))
  assert.ok(project.includes('DEVELOPMENT_TEAM = "ABCDEFGHIJ"'))
  assert.equal(readFileSync(join(original, 'project.pbxproj'), 'utf8'), 'personal Xcode settings')
})
