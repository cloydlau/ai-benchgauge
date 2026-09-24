import { spawn, spawnSync } from 'node:child_process'
import { copyFileSync, existsSync, mkdtempSync, readdirSync, readFileSync, rmSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { fileURLToPath } from 'node:url'

export function projectName() {
  return 'AI-BenchGauge'
}

export function notifyDesktop(root, title, message, {
  env = process.env,
  platform = process.platform,
  kind = 'success',
  image = '',
  wait = false,
} = {}) {
  if (env.DESKTOP_NOTIFY === '0' || platform !== 'darwin') return false
  const worker = fileURLToPath(new URL('./desktop-notify-worker.mjs', import.meta.url))
  const args = [worker, kind, `${projectName()} · ${title}`, message || ' ', image || '']
  const childEnv = {
    ...env,
    LOCAL_CI_NOTIFY_DIR: env.LOCAL_CI_NOTIFY_DIR || join(root, 'work', 'notify-apps'),
  }
  if (wait) {
    const result = spawnSync(process.execPath, args, {
      cwd: root,
      env: childEnv,
      stdio: 'inherit',
      timeout: 90_000,
    })
    return !result.error && result.status === 0
  }
  try {
    const child = spawn(process.execPath, args, {
      cwd: root,
      env: childEnv,
      stdio: 'ignore',
      detached: true,
    })
    child.on('error', (error) => console.warn(`[desktop-notify] 通知进程启动失败：${error.message}`))
    child.unref()
  } catch (error) {
    console.warn(`[desktop-notify] 通知进程启动失败：${error.message}`)
    return false
  }
  return true
}

function looksLikeSvg(path) {
  try {
    return readFileSync(path).subarray(0, 256).toString('utf8').includes('<svg')
  } catch {
    return false
  }
}

function rasterizeAvatar(source, png) {
  const converted = spawnSync('/usr/bin/sips', ['-s', 'format', 'png', source, '--out', png], { stdio: 'ignore' })
  if (converted.status === 0 && existsSync(png)) return true
  if (!looksLikeSvg(source)) return false
  const directory = mkdtempSync(join(tmpdir(), 'leaderboard-avatar-thumb-'))
  const svg = join(directory, 'avatar.svg')
  try {
    copyFileSync(source, svg)
    const thumb = spawnSync('/usr/bin/qlmanage', ['-t', '-s', '128', '-o', directory, svg], {
      stdio: 'ignore',
      timeout: 8_000,
    })
    if (thumb.error || thumb.status !== 0) return false
    const produced = readdirSync(directory).find((name) => name.endsWith('.png'))
    if (!produced) return false
    copyFileSync(join(directory, produced), png)
    return existsSync(png)
  } catch {
    return false
  } finally {
    rmSync(directory, { recursive: true, force: true })
  }
}

export function materializeAvatar(avatar) {
  const urls = avatar?.candidates?.length ? avatar.candidates : avatar?.url ? [avatar.url] : []
  if (urls.length === 0) return ''
  const directory = mkdtempSync(join(tmpdir(), 'leaderboard-avatar-'))
  const downloaded = join(directory, 'avatar')
  const png = join(directory, 'avatar.png')
  for (const url of urls) {
    const curl = spawnSync('/usr/bin/curl', ['-fsSL', '--max-time', '3', '-A', 'AI-BenchGauge', '-o', downloaded, url], { stdio: 'ignore' })
    if (curl.status !== 0 || !existsSync(downloaded)) continue
    if (rasterizeAvatar(downloaded, png)) return png
  }
  return ''
}

function main() {
  const args = process.argv.slice(2)
  const wait = args.includes('--wait')
  const rest = args.filter((arg) => arg !== '--wait')
  const [kind, title, message, image] = rest
  if (!kind || !title) {
    console.error('用法：node Scripts/desktop-notify.mjs [--wait] <success|failure> <标题> <正文> [图片]')
    process.exitCode = 1
    return
  }
  const ok = notifyDesktop(process.cwd(), title, message, { kind, image, wait })
  if (wait && !ok) process.exitCode = 1
}

if (process.argv[1] && process.argv[1].endsWith('desktop-notify.mjs')) main()
