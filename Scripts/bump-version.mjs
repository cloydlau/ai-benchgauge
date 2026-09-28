#!/usr/bin/env node
import { execFileSync } from 'node:child_process'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import { compareVersions, releaseVersion } from './release-lib.mjs'

try {
  const root = resolve(dirname(fileURLToPath(import.meta.url)), '..')
  const plist = join(root, 'Sources', 'LeaderboardMenu', 'Resources', 'Info.plist')
  const version = releaseVersion(process.argv[2])
  const info = JSON.parse(execFileSync('plutil', ['-convert', 'json', '-o', '-', plist], { encoding: 'utf8' }))
  const previous = (info.CFBundleVersion.split('.').length === 2 ? info.CFBundleVersion + '.0' : info.CFBundleVersion)
  if (compareVersions(version, previous) <= 0) throw new Error(`Version must be newer than ${info.CFBundleVersion}`)
  for (const name of ['CFBundleShortVersionString', 'CFBundleVersion']) {
    execFileSync('plutil', ['-replace', name, '-string', version, plist])
  }
  console.log(`Version -> ${version} (build ${version})`)
} catch (error) {
  console.error(`[version] ${error.message}`)
  process.exitCode = 1
}
