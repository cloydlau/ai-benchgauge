import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'

const read = path => readFileSync(new URL('../' + path, import.meta.url), 'utf8')
const identity = JSON.parse(read('Sources/LeaderboardKit/Resources/ApplicationLicense.json'))

test('the displayed application license matches the current terms and packaged Apple copies', () => {
  const license = read('LICENSE')
  assert.ok(license.includes(`The unmodified ${identity.name} follows.`), 'License identity drifted from the actual project terms')
  assert.ok(identity.name.startsWith(identity.shortName))
  for (const path of ['apps/macos/Sources/Resources/Licenses/AI-BenchGauge.txt', 'apps/ios/UI/Resources/AI-BenchGauge.txt']) {
    assert.equal(read(path), license, path)
  }
  assert.ok(read('apps/windows/BenchGauge/BenchGauge.csproj').includes('Include="../../../LICENSE" Link="Licenses/AI-BenchGauge.txt"'))
})

test('desktop application labels and exports share the identity instead of identifying the app as MIT', () => {
  const mac = read('apps/macos/Sources/LeaderboardView.swift')
  assert.ok(mac.includes('ApplicationLicense.shortName'))
  assert.ok(mac.includes('.help(ApplicationLicense.name)'))
  assert.doesNotMatch(mac, /"(?:MIT|MIT License|Cloyd Lau · MIT License)"/)
  assert.ok(read('apps/macos/Sources/LicenseNoticesView.swift').includes('license: ApplicationLicense.name'))
  const windows = read('apps/windows/BenchGauge/MainWindow.Appearance.cs')
  assert.ok(windows.includes('applicationLicense.ToolTip = ApplicationLicense.Name'))
  assert.doesNotMatch(windows, /FooterButton\("MIT License"/)
  for (const file of ['Package.swift', 'apps/windows/BenchGauge.Shared/BenchGauge.Shared.csproj']) {
    assert.ok(read(file).includes('Resources/ApplicationLicense.json'), file)
  }
})
