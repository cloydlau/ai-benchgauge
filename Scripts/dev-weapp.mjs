import { spawn } from 'node:child_process'
import { startWeappUploadWatch } from './weapp-deploy.mjs'
import { ci } from './calmmit.mjs'

const stop = await startWeappUploadWatch()
const child = spawn('pnpm', ['--filter', '@benchgauge/weapp', 'dev'], { cwd: ci.root, env: process.env, stdio: 'inherit' })
child.once('error', error => { stop(); console.error(error.message); process.exitCode = 1 })
child.once('close', code => { stop(); process.exit(code ?? 1) })
for (const signal of ['SIGINT', 'SIGTERM']) process.once(signal, () => { stop(); child.kill(signal) })
