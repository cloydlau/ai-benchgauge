import { readFileSync, existsSync, readdirSync, statSync } from 'node:fs'
import { dirname, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const root = fileURLToPath(new URL('../dist/', import.meta.url))
const app = JSON.parse(readFileSync(resolve(root, 'app.json')))
for (const page of app.pages) {
  for (const extension of ['js', 'json', 'wxml', 'wxss']) {
    if (!existsSync(resolve(root, `${page}.${extension}`))) throw new Error(`Missing page output: ${page}.${extension}`)
  }
}
function inspect(directory) {
  for (const name of readdirSync(directory)) {
    const path = resolve(directory, name)
    if (statSync(path).isDirectory()) { inspect(path); continue }
    if (name.endsWith('.json')) {
      const config = JSON.parse(readFileSync(path, 'utf8'))
      for (const component of Object.values(config.usingComponents || {})) {
        const base = component.startsWith('/') ? resolve(root, component.slice(1)) : resolve(dirname(path), component)
        for (const suffix of ['.js', '.json', '.wxml', '.wxss']) {
          if (!existsSync(base + suffix)) throw new Error(`Missing component output: ${component}${suffix}`)
        }
      }
    }
    if (name.endsWith('.js')) {
      const code = readFileSync(path, 'utf8')
      for (const match of code.matchAll(/require\(["'](\.[^"']+)["']\)/g)) {
        const dependency = resolve(dirname(path), match[1])
        if (!['', '.js', '/index.js'].some(suffix => existsSync(dependency + suffix))) throw new Error(`Missing runtime module: ${match[1]} in ${path}`)
      }
      if (/\b__(SHARED_ENDPOINT|APP_VERSION|MIT_LICENSE|THIRD_PARTY_NOTICES)__\b/.test(code)) throw new Error(`Unresolved build constant: ${path}`)
    }
  }
}
inspect(root)
if (!existsSync(resolve(root, 'assets/header-logo.png'))) throw new Error('Missing existing brand asset')
for (const glyph of ['zh-I', 'zh-tian', 'zh-ti', 'en-I', 'en-name']) {
  for (const theme of ['', '-dark']) {
    if (!existsSync(resolve(root, `assets/brand-glyphs/${glyph}${theme}.svg`))) throw new Error(`Missing native title glyph: ${glyph}${theme}`)
  }
}
if (!existsSync(resolve(root, 'assets/brand-glyphs/LICENSE.txt'))) throw new Error('Missing title font license')
if (!existsSync(resolve(root, 'app.wxss'))) throw new Error('Missing global styles')
console.log(`Verified ${app.pages.length} pages, assets and all relative runtime modules.`)
