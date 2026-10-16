import { readFileSync, writeFileSync } from 'node:fs'
import { copy, text } from '../apps/weapp/src/core/catalog.js'

const check = process.argv.includes('--check')
const block = /<!-- app-description:start[^\n]* -->\n[\s\S]*?\n<!-- app-description:end -->/g
for (const [file, language] of [['README.md', 'en'], ['README.zh-CN.md', 'zh-CN'], ['README.zh-Hant.md', 'zh-TW']]) {
  const path = new URL(`../${file}`, import.meta.url)
  const original = readFileSync(path, 'utf8')
  if ([...original.matchAll(block)].length !== 1) throw new Error(`Expected one app description block in ${file}`)
  const generated = `<!-- app-description:start (generated from apps/weapp/src/core/catalog.js) -->\n**${text(copy.description, language)}**\n<!-- app-description:end -->`
  const updated = original.replace(block, () => generated)
  if (updated === original) continue
  if (check) throw new Error(`${file}: app description is out of date; run pnpm sync:description`)
  writeFileSync(path, updated)
}
console.log(`App descriptions ${check ? 'verified' : 'synced'} in all three READMEs.`)
