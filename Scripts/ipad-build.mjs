#!/usr/bin/env node
import { spawnSync } from 'node:child_process'
import { mkdirSync } from 'node:fs'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import { generateIpadProject } from './ipad-project.mjs'

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..')
export function ipadSimulator(devices, family = 'iPad') {
  if (!['iPad', 'iPhone'].includes(family)) throw new Error('Unsupported simulator family.')
  for (const [runtime, list] of Object.entries(devices.devices ?? {}).sort(([a], [b]) => b.localeCompare(a, undefined, { numeric: true }))) {
    const version = /iOS-(\d+)/.exec(runtime)
    if (!version || Number(version[1]) < 17) continue
    const device = list.find(value => value.isAvailable && value.name.startsWith(family) && /^[A-Fa-f0-9-]{36}$/.test(value.udid))
    if (device) return device.udid
  }
  throw new Error(`Install an available ${family} simulator running iOS / iPadOS 17 or later in Xcode Settings → Platforms.`)
}
export function ipadBuildPlan(mode, { directory = root, device, phone, team = '' } = {}) {
  const base = ['-project', join(directory, 'apps/ipad/AI-BenchGauge.xcodeproj'), '-scheme', 'BenchGauge',
    '-derivedDataPath', join(directory, 'work/ipad-build')]
  if (mode === 'archive') {
    if (!/^[A-Z0-9]{10}$/.test(team)) throw new Error('Set APPLE_TEAM_ID to your Apple Developer team ID before archiving.')
    return [[...base, '-configuration', 'Release', '-destination', 'generic/platform=iOS', '-archivePath',
      join(directory, 'work/ipad/AI-BenchGauge.xcarchive'), `DEVELOPMENT_TEAM=${team}`, 'archive']]
  }
  if (!['check', 'test'].includes(mode)) throw new Error('Usage: node Scripts/ipad-build.mjs [check | test | archive]')
  if (![device, phone].every(id => /^[A-Fa-f0-9-]{36}$/.test(id ?? ''))) throw new Error('Valid iPad and iPhone simulator IDs are required.')
  const tests = [['iPad', device], ['iPhone', phone]].map(([family, id]) => [
    ...base, '-destination', `platform=iOS Simulator,id=${id}`, '-configuration', 'Debug', '-resultBundlePath',
    join(directory, `work/ipad/${family}-TestResults-${Date.now()}.xcresult`),
    '-parallel-testing-enabled', 'NO', 'CODE_SIGNING_ALLOWED=NO', 'test',
  ])
  return mode === 'test' ? tests : [
    [...base, '-configuration', 'Release', '-destination', 'generic/platform=iOS Simulator', 'CODE_SIGNING_ALLOWED=NO', 'build'],
    [...base, '-configuration', 'Release', '-destination', 'generic/platform=iOS', 'CODE_SIGNING_ALLOWED=NO', 'build'], ...tests,
  ]
}
export function runIpadBuild(mode = 'check', env = process.env) {
  const sdk = spawnSync('xcrun', ['--sdk', mode === 'archive' ? 'iphoneos' : 'iphonesimulator', '--show-sdk-path'], { encoding: 'utf8' })
  if (sdk.status !== 0) throw new Error('Full Xcode with the iOS SDK is required. Command Line Tools alone cannot build the iPhone / iPad app. Select Xcode with xcode-select, or run the iPad GitHub Actions check.')
  const team = env.APPLE_TEAM_ID || ''
  generateIpadProject(root, { team, buildNumber: env.IPAD_BUILD_NUMBER || '1' })
  let device, phone
  if (mode !== 'archive') {
    const result = spawnSync('xcrun', ['simctl', 'list', 'devices', 'available', '--json'], { encoding: 'utf8' })
    if (result.status !== 0) throw new Error('Unable to read Xcode simulators.')
    const available = JSON.parse(result.stdout)
    device = ipadSimulator(available)
    phone = ipadSimulator(available, 'iPhone')
    console.log(`[iOS] Native test destinations: iPad ${device}; iPhone ${phone}`)
    const selected = Object.entries(available.devices).flatMap(([runtime, list]) =>
      list.filter(value => [device, phone].includes(value.udid)).map(value => ({ runtime, name: value.name, udid: value.udid })))
    console.log(JSON.stringify({ nativeDestinations: selected }))
  }
  mkdirSync(join(root, 'work/ipad'), { recursive: true })
  for (const args of ipadBuildPlan(mode, { device, phone, team })) {
    const result = spawnSync('xcodebuild', args, { cwd: root, env, stdio: 'inherit' })
    if (result.error) throw result.error
    if (result.status !== 0) return result.status ?? 1
  }
  return 0
}
if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try { process.exitCode = runIpadBuild(process.argv[2] || 'check') }
  catch (error) { console.error(`[ipad] ${error.message}`); process.exitCode = 1 }
}
