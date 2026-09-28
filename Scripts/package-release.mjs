#!/usr/bin/env node
import { spawnSync } from 'node:child_process'
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import { validateAppConfig } from './app-config.mjs'
import { renderAppcast, sha256, signArchive, signingKey, validateRelease } from './release-lib.mjs'

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..')
function run(command, args, options = {}) {
  const childEnv = { ...process.env }
  delete childEnv.SPARKLE_PRIVATE_KEY
  const result = spawnSync(command, args, { encoding: 'utf8', env: childEnv, ...options })
  if (result.status !== 0 || result.error) throw new Error(`${command} failed: ${result.stderr || result.error?.message || result.stdout}`)
  return result.stdout.trim()
}

try {
  const tag = process.argv[2] || process.env.GITHUB_REF_NAME
  const app = join(root, 'outputs', 'AI-BenchGauge.app')
  const info = JSON.parse(run('plutil', ['-convert', 'json', '-o', '-', join(app, 'Contents', 'Info.plist')]))
  const version = validateRelease(tag, info)
  const config = validateAppConfig(root, tag)
  if (info.SUPublicEDKey !== config.updatePublicKey) throw new Error('Packaged update key differs from shared configuration')
  const seed = process.env.SPARKLE_PRIVATE_KEY?.trim()
  if (!seed) throw new Error('SPARKLE_PRIVATE_KEY is required to package a signed update')
  const key = signingKey(seed, info.SUPublicEDKey)
  // Drop the secret before starting packaging tools or signing subprocesses.
  delete process.env.SPARKLE_PRIVATE_KEY
  run('codesign', ['--verify', '--deep', '--strict', app])
  const architectures = run('lipo', ['-archs', join(app, 'Contents', 'MacOS', 'leaderboard-menu')]).split(/\s+/)
  if (!architectures.includes('arm64') || !architectures.includes('x86_64')) throw new Error('Release must include both arm64 and x86_64')
  const directory = join(root, 'outputs', 'release')
  mkdirSync(directory, { recursive: true })
  const archiveName = `AI-BenchGauge-${version}-macos-universal.dmg`
  const archive = join(directory, archiveName)
  const staging = join(root, 'work', 'dmg-staging')
  run('mkdir', ['-p', staging])
  run('ditto', [app, join(staging, 'AI-BenchGauge.app')])
  run('ln', ['-sfn', '/Applications', join(staging, 'Applications')])
  run('hdiutil', ['create', '-volname', 'AI BenchGauge', '-srcfolder', staging, '-ov', '-format', 'UDZO', archive])
  const bytes = readFileSync(archive)
  const signature = signArchive(bytes, key)
  const notes = process.env.RELEASE_NOTES_FILE ? readFileSync(process.env.RELEASE_NOTES_FILE, 'utf8') : `AI BenchGauge ${version}\n\nSee the GitHub Release for changes.`
  const appcast = join(directory, 'appcast.xml')
  writeFileSync(appcast, renderAppcast({ version, archiveName, signature, length: bytes.length, notes }))
  const signer = join(root, '.build', 'artifacts', 'sparkle', 'Sparkle', 'bin', 'sign_update')
  run(signer, ['-f', '-', '-p', appcast], { input: seed + '\n' })
  run(signer, ['-f', '-', '--verify', appcast], { input: seed + '\n' })
  run(signer, ['-f', '-', '--verify', archive, signature], { input: seed + '\n' })
  writeFileSync(join(directory, 'release-notes.md'), notes)
  writeFileSync(join(directory, 'SHA256SUMS.txt'), [archiveName, 'appcast.xml'].map((name) => `${sha256(readFileSync(join(directory, name)))}  ${name}`).join('\n') + '\n')
  console.log(`Signed and verified ${archiveName} and appcast.xml in outputs/release/`)
} catch (error) {
  console.error(`[release] ${error.message}`)
  process.exitCode = 1
}
