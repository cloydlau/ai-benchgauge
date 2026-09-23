// 成功和失败使用两个 macOS 应用身份，通知样式由系统按应用记住。
// 已安装且版本一致的 Local CI Success/Failure 直接复用，避免覆盖同一 bundle。
import { spawnSync } from 'node:child_process'
import {
  existsSync, mkdirSync, mkdtempSync, readFileSync, renameSync, rmSync, writeFileSync,
} from 'node:fs'
import { homedir, tmpdir } from 'node:os'
import { join } from 'node:path'
import { fileURLToPath } from 'node:url'

const revision = '4'
const source = fileURLToPath(new URL('./desktop-notify-settings.m', import.meta.url))

function run(command, args, options = {}) {
  const result = spawnSync(command, args, { encoding: 'utf8', timeout: 60_000, ...options })
  if (result.error || result.status !== 0) {
    throw new Error(result.error?.message || (result.stderr || '').trim() || `${command} 退出码 ${result.status}`)
  }
  return result.stdout || ''
}

export function notificationAppName(kind) {
  if (kind === 'failure') return 'Local CI Failure'
  if (kind === 'success') return 'Local CI Success'
  throw new Error(`未知通知类型：${kind}`)
}

export function ensureNotificationApp(kind, directory) {
  const name = notificationAppName(kind)
  const app = join(directory, `${name}.app`)
  const binary = join(app, 'Contents', 'MacOS', 'notification-settings')
  const marker = join(app, 'Contents', 'Resources', 'notification-revision')
  const current = () => {
    try {
      return existsSync(binary) && existsSync(marker) && readFileSync(marker, 'utf8') === revision
    } catch {
      return false
    }
  }
  if (current()) return app
  mkdirSync(directory, { recursive: true })
  const staging = mkdtempSync(join(directory, '.local-ci-notify-'))
  try {
    const compiled = join(staging, `${name}.app`)
    mkdirSync(join(compiled, 'Contents', 'MacOS'), { recursive: true })
    mkdirSync(join(compiled, 'Contents', 'Resources'))
    const plist = join(compiled, 'Contents', 'Info.plist')
    writeFileSync(plist, JSON.stringify({
      CFBundleIdentifier: `local.limphase.ci.${kind}`,
      CFBundleName: name,
      CFBundleDisplayName: name,
      CFBundleExecutable: 'notification-settings',
      CFBundlePackageType: 'APPL',
      CFBundleVersion: revision,
      CFBundleShortVersionString: revision,
    NSUserNotificationAlertStyle: 'banner',
      LSUIElement: true,
    }))
    run('/usr/bin/plutil', ['-convert', 'xml1', plist])
    const compiledBinary = join(compiled, 'Contents', 'MacOS', 'notification-settings')
    run('/usr/bin/xcrun', ['clang', '-fobjc-arc', '-framework', 'Foundation', '-framework', 'UserNotifications', source, '-o', compiledBinary])
    run('/usr/bin/codesign', ['--force', '--sign', '-', '--identifier', `local.limphase.ci.${kind}`, compiledBinary])
    writeFileSync(join(compiled, 'Contents', 'Resources', 'notification-revision'), revision)
    run('/usr/bin/codesign', ['--force', '--sign', '-', compiled])
    if (current()) return app
    renameSync(compiled, app)
    return app
  } catch (error) {
    if (current()) return app
    throw error
  } finally {
    rmSync(staging, { recursive: true, force: true })
  }
}

function appDirectories() {
  const fallback = process.env.LOCAL_CI_NOTIFY_DIR || join(process.cwd(), 'work', 'notify-apps')
  const homeApps = join(homedir(), 'Applications')
  return homeApps === fallback ? [homeApps] : [homeApps, fallback]
}

function permissionFailure(error) {
  return /permission|disabled|not granted|alerts disabled|Notification rejected/i.test(error?.message || '')
}

export function deliverNotification(kind, title, message, image) {
  let lastError = null
  for (const directory of appDirectories()) {
    try {
      const app = ensureNotificationApp(kind, directory)
      const temp = mkdtempSync(join(tmpdir(), 'leaderboard-notify-'))
      try {
        const payload = join(temp, 'notification.json')
        writeFileSync(payload, JSON.stringify({
          title: String(title || '').replace(/[\r\n]/g, ' '),
          message: message || ' ',
          image: image || '',
        }))
        const receipt = JSON.parse(run(join(app, 'Contents', 'MacOS', 'notification-settings'), ['--send', payload]))
        if (receipt?.accepted !== true) throw new Error('通知发送缺少系统回执')
        return receipt
      } finally {
        rmSync(temp, { recursive: true, force: true })
      }
    } catch (error) {
      lastError = error
      if (permissionFailure(error)) break
    }
  }
  throw lastError || new Error('无法发送通知')
}

function displayWithOsascript(title, message) {
  const script = `on run argv
    display notification (item 2 of argv) with title (item 1 of argv)
  end run`
  run('/usr/bin/osascript', ['-e', script, title, message])
}

function cleanupImage(image) {
  if (image && image.includes('leaderboard-avatar-')) rmSync(image, { force: true })
}

function main() {
  const [kind, title, message, image] = process.argv.slice(2)
  try {
    const receipt = deliverNotification(kind, title, message, image)
    console.log(`[desktop-notify] 系统已接受通知：${receipt.notificationId}`)
  } catch (error) {
    console.warn(`[desktop-notify] 原生通知失败：${error.message}`)
    try {
      displayWithOsascript(title, message)
      console.log('[desktop-notify] 已改用 osascript 发送')
    } catch (fallbackError) {
      console.error(`[desktop-notify] ${fallbackError.message}`)
      process.exitCode = 1
    }
  } finally {
    cleanupImage(image)
  }
}

if (process.argv[1] && process.argv[1].endsWith('desktop-notify-worker.mjs')) main()
