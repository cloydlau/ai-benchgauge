#!/usr/bin/env node
import { spawnSync } from 'node:child_process'
import { existsSync, mkdirSync } from 'node:fs'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import { decodePublicKey } from './release-lib.mjs'

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..')
const account = 'com.cloydlau.ai-benchgauge'
const generator = join(root, '.build', 'artifacts', 'sparkle', 'Sparkle', 'bin', 'generate_keys')
function run(command, args) {
  const result = spawnSync(command, args, { encoding: 'utf8' })
  if (result.status !== 0 || result.error) throw new Error(result.stderr || result.stdout || result.error?.message)
  return result.stdout.trim()
}
try {
  process.umask(0o077)
  if (!existsSync(generator)) throw new Error('Run ./make-app.sh first to download Sparkle')
  if (process.argv.length > 2 && process.argv[2] !== '--export-key') throw new Error('Usage: node Scripts/setup-updates.mjs [--export-key]')
  // This creates the project key once and reuses it thereafter, in login Keychain.
  run(generator, ['--account', account])
  const publicKey = run(generator, ['--account', account, '-p'])
  decodePublicKey(publicKey)
  const plist = join(root, 'Sources', 'LeaderboardMenu', 'Resources', 'Info.plist')
  const existing = JSON.parse(run('plutil', ['-convert', 'json', '-o', '-', plist])).SUPublicEDKey
  if (existing && existing !== publicKey) throw new Error('The existing public key differs. Import the original signing key into Keychain; do not rotate it automatically.')
  run('plutil', ['-replace', 'SUPublicEDKey', '-string', publicKey, plist])
  console.log('Update public key configured. The private key stays in your login Keychain.')
  if (process.argv[2] === '--export-key') {
    const directory = join(root, 'work', 'update-signing')
    mkdirSync(directory, { recursive: true, mode: 0o700 })
    const privateFile = join(directory, 'sparkle-private-key.txt')
    run(generator, ['--account', account, '-x', privateFile])
    console.log('Exported to ignored work/update-signing/sparkle-private-key.txt for GitHub Secret SPARKLE_PRIVATE_KEY. Delete the export after uploading it.')
  }
} catch (error) {
  console.error(`[updates] ${error.message}`)
  process.exitCode = 1
}
