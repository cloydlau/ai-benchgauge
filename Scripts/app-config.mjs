import { readFileSync } from 'node:fs'
import { join } from 'node:path'
import { decodePublicKey, releaseVersion, repository } from './release-lib.mjs'
export function readAppConfig(root) {
  const config = JSON.parse(readFileSync(join(root, 'config/app.json'), 'utf8'))
  if ('previewCCSwitchEmptyState' in config) {
    throw new Error('Use previewCCSwitchState instead of previewCCSwitchEmptyState')
  }
  if (config.previewCCSwitchState !== undefined && config.previewCCSwitchState !== null
    && !['notInstalled', 'installedEmpty', 'configured'].includes(config.previewCCSwitchState)) {
    throw new Error('previewCCSwitchState must be notInstalled, installedEmpty, configured, or null')
  }
  releaseVersion(config.version); decodePublicKey(config.updatePublicKey)
  if (config.repository !== repository) throw new Error('Unexpected release repository')
  if (config.previewCCSwitchState != null && !['notInstalled', 'installedEmpty', 'configured'].includes(config.previewCCSwitchState)) {
    throw new Error('previewCCSwitchState must be null, notInstalled, installedEmpty or configured')
  }
  return config
}
export function plistString(text, key) {
  if (text.trim().startsWith('{')) return JSON.parse(text)[key]
  const match = new RegExp(`<key>${key}</key>\\s*<string>([^<]*)</string>`).exec(text)
  if (!match) throw new Error(`Missing Info.plist string ${key}`)
  return match[1]
}
export function validateAppConfig(root, tag) {
  const config = readAppConfig(root)
  const plist = readFileSync(join(root, 'apps/macos/Sources/Resources/Info.plist'), 'utf8')
  if (['CFBundleVersion', 'CFBundleShortVersionString'].some(key => plistString(plist, key) !== config.version)
    || plistString(plist, 'SUPublicEDKey') !== config.updatePublicKey) throw new Error('macOS and Windows release configuration must match')
  if (tag && tag !== `v${config.version}`) throw new Error('Release tag must match the shared application version')
  return config
}
