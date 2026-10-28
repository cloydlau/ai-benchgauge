import { mkdtempSync, mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'

// Exercise local-avatar behavior without depending on supplier artwork shipped
// by the application. This one-pixel fixture contains no third-party artwork.
export function avatarFixture(t) {
  const root = mkdtempSync(join(tmpdir(), 'benchgauge-avatar-fixture-'))
  t.after(() => rmSync(root, { recursive: true, force: true }))
  const { identity } = JSON.parse(readFileSync(new URL('../../calmmit.config.json', import.meta.url), 'utf8'))
  const directory = 'avatars'
  mkdirSync(join(root, directory))
  const png = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=', 'base64')
  for (const file of Object.values(identity.avatarFiles)) writeFileSync(join(root, directory, file), png)
  return { root, config: { identity: { ...identity, avatarDirectory: directory } } }
}
