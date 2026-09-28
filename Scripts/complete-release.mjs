#!/usr/bin/env node
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import { validateAppConfig } from './app-config.mjs'
import { repository, sha256, signArchive, signingKey } from './release-lib.mjs'
const root = resolve(dirname(fileURLToPath(import.meta.url)), '..')
try {
  const config = validateAppConfig(root, process.argv[2] || process.env.GITHUB_REF_NAME)
  const version = config.version
  const key = signingKey(process.env.SPARKLE_PRIVATE_KEY?.trim(), config.updatePublicKey)
  delete process.env.SPARKLE_PRIVATE_KEY
  const directory = join(root, 'outputs/release'); mkdirSync(directory, { recursive: true })
  const mac = `AI-BenchGauge-${version}-macos-universal.dmg`
  const windows = `AI-BenchGauge-${version}-windows-x64-setup.exe`
  const macBytes = readFileSync(join(directory, mac)); const windowsBytes = readFileSync(join(directory, windows))
  if (macBytes.length < 512 || windowsBytes.length < 512 || windowsBytes.subarray(0, 2).toString() !== 'MZ') throw new Error('Invalid platform installers')
  const feed = readFileSync(join(directory, 'appcast.xml'), 'utf8')
  if (!feed.includes(`/v${version}/${mac}`)) throw new Error('macOS feed does not match this release')
  const notes = readFileSync(join(directory, 'release-notes.md'), 'utf8')
  const payload = Buffer.from(JSON.stringify({ version, url: `https://github.com/${repository}/releases/download/v${version}/${windows}`,
    sha256: sha256(windowsBytes), length: windowsBytes.length, notes: notes.slice(0, 12_000) }, null, 2) + '\n')
  if (payload.length > 65_536) throw new Error('Windows update metadata exceeds limit')
  writeFileSync(join(directory, 'windows-update.json'), payload)
  writeFileSync(join(directory, 'windows-update.json.sig'), signArchive(payload, key) + '\n')
  const assets = [mac, windows, 'appcast.xml', 'windows-update.json', 'windows-update.json.sig']
  writeFileSync(join(directory, 'SHA256SUMS.txt'), assets.map(name => `${sha256(readFileSync(join(directory, name)))}  ${name}`).join('\n') + '\n')
  console.log(`Verified both installers and signed Windows updates for ${version}`)
} catch (error) { console.error(`[release] ${error.message}`); process.exitCode = 1 }
