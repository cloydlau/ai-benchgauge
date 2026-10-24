import { createRequire } from 'node:module'
import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { resolve } from 'node:path'

// Isolated npm + Node compiler; weapp-deploy configures compatibility flags.
const runtime = fileURLToPath(new URL('../ci-runtime/package.json', import.meta.url))
const ci = createRequire(runtime)('miniprogram-ci')
const [projectPath, appid, privateKeyPath, version] = process.argv.slice(2)
if (!projectPath || !appid || !privateKeyPath || !version) throw new Error('请通过 pnpm upload:weapp 上传')
const pkg = JSON.parse(readFileSync(resolve(projectPath, 'package.json'), 'utf8'))
const description = process.env.MP_DESC || pkg.uploadDescription
process.env.NODE_OPTIONS = `${(process.env.NODE_OPTIONS || '').replace(/--(?:no-)?preserve-symlinks\b/g, '')} --no-preserve-symlinks`
const project = new ci.Project({ appid, type: 'miniProgram', projectPath: resolve(projectPath), privateKeyPath,
  ignores: ['node_modules/**/*', 'src/**/*', 'test/**/*', 'scripts/**/*', 'ci-runtime/**/*'] })
await ci.upload({ project, version, desc: description, robot: 1,
  setting: { es6: false, es7: false, minify: false, minifyJS: false, minifyWXSS: false,
    minifyWXML: true, autoPrefixWXSS: false, codeProtect: true },
  onProgressUpdate() {},
})
console.log(`[weapp-upload] 微信已接收 ${appid} 开发版 ${version}`)
