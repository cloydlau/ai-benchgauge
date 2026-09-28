#!/usr/bin/env node
import { readFileSync, writeFileSync } from 'node:fs'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import { compareVersions, releaseVersion } from './release-lib.mjs'
import { validateAppConfig } from './app-config.mjs'
try {
  const root = resolve(dirname(fileURLToPath(import.meta.url)), '..')
  const config = validateAppConfig(root)
  const version = releaseVersion(process.argv[2])
  if (compareVersions(version, config.version) <= 0) throw new Error(`Version must be newer than ${config.version}`)
  const plist = join(root, 'apps/macos/Sources/Resources/Info.plist')
  const original = readFileSync(plist, 'utf8')
  let updated
  if (original.trim().startsWith('{')) updated = JSON.stringify({ ...JSON.parse(original), CFBundleVersion: version, CFBundleShortVersionString: version }, null, 2) + '\n'
  else updated = original.replace(/(<key>CFBundle(?:ShortVersionString|Version)<\/key>\s*<string>)[^<]+(<\/string>)/g, `$1${version}$2`)
  writeFileSync(plist, updated)
  writeFileSync(join(root, 'config/app.json'), JSON.stringify({ ...config, version }, null, 2) + '\n')
  console.log(`macOS + Windows version -> ${version}`)
} catch (error) { console.error(`[version] ${error.message}`); process.exitCode = 1 }
