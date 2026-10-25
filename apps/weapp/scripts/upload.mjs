import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { ci } from '../../../Scripts/calmmit.mjs'

const { createWechatCiUploader } = await ci.load('wechat-ci')
const [projectPath, appid, privateKeyPath, version] = process.argv.slice(2)
if (!projectPath || !appid || !privateKeyPath || !version) throw new Error('请通过 pnpm upload:weapp 上传')
const pkg = JSON.parse(readFileSync(resolve(projectPath, 'package.json'), 'utf8'))
const uploader = createWechatCiUploader({
  root: ci.root, projectPath, appid, privateKeyPath, version,
  description: process.env.MP_DESC || pkg.uploadDescription,
})
await uploader.upload()
console.log(`[weapp-upload] 微信已接收 ${appid} 开发版 ${version}`)
