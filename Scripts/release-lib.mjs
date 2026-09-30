import { createHash, createPrivateKey, createPublicKey, sign, verify } from 'node:crypto'

export const repository = 'cloydlau/ai-benchgauge'
export const feedURL = `https://github.com/${repository}/releases/latest/download/appcast.xml`

export function releaseVersion(value) {
  const match = /^v?((?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*))$/.exec(value ?? '')
  if (!match) throw new Error('Release version must be a stable version, for example 1.2.3 or v1.2.3')
  return match[1]
}

export function compareVersions(left, right) {
  const a = releaseVersion(left).split('.').map(BigInt)
  const b = releaseVersion(right).split('.').map(BigInt)
  for (let i = 0; i < 3; i++) if (a[i] !== b[i]) return a[i] > b[i] ? 1 : -1
  return 0
}

export function validateRelease(tag, info, published = []) {
  const version = releaseVersion(tag)
  if (tag !== `v${version}` || info.CFBundleShortVersionString !== version || info.CFBundleVersion !== version) {
    throw new Error('The tag, marketing version, and build version must match')
  }
  if (info.CFBundleIdentifier !== 'com.cloydlau.ai-benchgauge' || info.LSMinimumSystemVersion !== '14.0') {
    throw new Error('Unexpected bundle identifier or deployment target')
  }
  if (info.SUFeedURL !== feedURL || info.SUScheduledCheckInterval !== 86400 || info.SUEnableAutomaticChecks !== true
      || info.SUAutomaticallyUpdate !== false || info.SUAllowsAutomaticUpdates !== false
      || info.SURequireSignedFeed !== true || info.SUVerifyUpdateBeforeExtraction !== true) {
    throw new Error('The release must use the signed 24-hour update feed and require an Install click')
  }
  decodePublicKey(info.SUPublicEDKey)
  for (const prior of published.filter((item) => !item.isDraft && !item.isPrerelease)) {
    if (compareVersions(version, prior.tagName) <= 0) throw new Error(`Release must be newer than ${prior.tagName}`)
  }
  return version
}

export function decodePublicKey(encoded) {
  if (!/^[A-Za-z0-9+/]{43}=$/.test(encoded ?? '') || Buffer.from(encoded, 'base64').length !== 32) {
    throw new Error('Configure SUPublicEDKey before publishing a release')
  }
  return Buffer.from(encoded, 'base64')
}

export function signingKey(encodedSeed, encodedPublicKey) {
  // Sparkle's current export format is a base64 encoded Ed25519 private seed.
  const seed = decodePublicKey(encodedSeed?.trim())
  const key = createPrivateKey({ format: 'der', type: 'pkcs8',
    key: Buffer.concat([Buffer.from('302e020100300506032b657004220420', 'hex'), seed]) })
  const actual = createPublicKey(key).export({ format: 'der', type: 'spki' }).subarray(-32)
  if (!actual.equals(decodePublicKey(encodedPublicKey))) throw new Error('The signing key does not match the application public key')
  return key
}

export function signArchive(data, key) {
  const signature = sign(null, data, key)
  if (!verify(null, data, createPublicKey(key), signature)) throw new Error('Archive signature verification failed')
  return signature.toString('base64')
}

export function escapeXML(text) {
  return String(text).replace(/[<>&"']/g, (c) => ({ '<': '&lt;', '>': '&gt;', '&': '&amp;', '"': '&quot;', "'": '&apos;' })[c])
}

export function renderAppcast({ version, archiveName, signature, length, notes, date = new Date() }) {
  version = releaseVersion(version)
  if (![ `AI-BenchGauge-${version}-macos-universal.zip`, `AI-BenchGauge-${version}-macos-universal.dmg` ].includes(archiveName)
      || Buffer.from(signature ?? '', 'base64').length !== 64 || !Number.isSafeInteger(length) || length <= 0) {
    throw new Error('Invalid update archive metadata')
  }
  const base = `https://github.com/${repository}/releases/download/v${version}`
  return `<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>AI BenchGauge Updates</title>
    <link>https://github.com/${repository}/releases</link>
    <description>AI BenchGauge stable releases</description>
    <item>
      <title>AI BenchGauge ${version}</title>
      <pubDate>${date.toUTCString()}</pubDate>
      <sparkle:version>${version}</sparkle:version>
      <sparkle:shortVersionString>${version}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <description><![CDATA[<pre>${escapeXML(notes)}</pre>]]></description>
      <link>https://github.com/${repository}/releases/tag/v${version}</link>
      <enclosure url="${base}/${archiveName}" length="${length}" type="application/octet-stream" sparkle:edSignature="${escapeXML(signature)}" />
    </item>
  </channel>
</rss>
`
}

export function renderHomebrewCask({ version, archiveName, digest }) {
  version = releaseVersion(version)
  if (archiveName !== `AI-BenchGauge-${version}-macos-universal.dmg` || !/^[0-9a-f]{64}$/.test(digest ?? '')) {
    throw new Error('Invalid Homebrew cask metadata')
  }
  return `cask "ai-benchgauge" do
  version "${version}"
  sha256 "${digest}"
  url "https://github.com/${repository}/releases/download/v${version}/${archiveName}"
  name "AI BenchGauge"
  desc "Menu-bar leaderboard and provider quota dashboard"
  homepage "https://github.com/${repository}"
  auto_updates true
  depends_on macos: ">= :sonoma"
  app "AI-BenchGauge.app"
end
`
}

export function sha256(data) { return createHash('sha256').update(data).digest('hex') }
