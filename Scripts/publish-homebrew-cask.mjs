#!/usr/bin/env node
import { readFileSync } from 'node:fs'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import { repository, releaseVersion } from './release-lib.mjs'

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..')
const token = process.env.GH_TOKEN
const tag = process.env.RELEASE_TAG
const version = releaseVersion(tag)
const caskPath = 'Casks/ai-benchgauge.rb'
const cask = readFileSync(join(root, 'outputs/release/ai-benchgauge.rb'), 'utf8')

if (!cask.includes(`version "${version}"`) || !cask.includes(`releases/download/v${version}/`)) {
  throw new Error('Generated Homebrew cask does not match this release')
}

const headers = {
  Authorization: `Bearer ${token}`,
  Accept: 'application/vnd.github+json',
  'X-GitHub-Api-Version': '2022-11-28'
}
const api = `https://api.github.com/repos/${repository}/contents/${encodeURIComponent(caskPath)}`
const current = await fetch(`${api}?ref=main`, { headers })
const existing = current.status === 404 ? undefined : await current.json()
if (!current.ok && current.status !== 404) throw new Error(`GitHub cask lookup failed: ${current.status} ${current.statusText}`)
if (existing?.content && Buffer.from(existing.content, 'base64').toString('utf8') === cask) process.exit(0)

const update = await fetch(api, {
  method: 'PUT',
  headers: { ...headers, 'Content-Type': 'application/json' },
  body: JSON.stringify({
    message: `chore: update Homebrew cask for v${version}`,
    content: Buffer.from(cask).toString('base64'),
    branch: 'main',
    ...(existing ? { sha: existing.sha } : {})
  })
})
if (!update.ok) throw new Error(`GitHub cask update failed: ${update.status} ${await update.text()}`)
console.log(`Published Homebrew cask for v${version}`)
