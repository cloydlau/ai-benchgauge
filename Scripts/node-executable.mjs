// pnpm 把 node runtime 放在内容寻址目录中，更新之后旧目录连同二进制一起消失。
// 长驻的 watch 进程仍持有启动时的 process.execPath，此后每次派生子进程都以
// ENOENT 失败，测试、提交、推送和桌面通知一起停摆。所以派生前先确认这个路径
// 还在；失效时改用 PATH 上的 node，并解析成子进程自己会上报的真实路径，
// 让父子进程算出的测试签名保持一致。

import { existsSync, realpathSync } from 'node:fs'
import { delimiter, join } from 'node:path'

export function nodeExecutable({
  env = process.env,
  execPath = process.execPath,
  platform = process.platform,
} = {}) {
  if (env.BENCHGAUGE_NODE) return env.BENCHGAUGE_NODE
  if (execPath && existsSync(execPath)) return execPath
  return nodeOnPath(env, platform) || execPath || 'node'
}

// 启动用的软链不够：子进程上报的是解析后的真实二进制，签名两边必须相同。
export function nodeOnPath(env = process.env, platform = process.platform) {
  const names = platform === 'win32' ? ['node.exe', 'node'] : ['node']
  for (const directory of String(env.PATH || '').split(delimiter)) {
    if (!directory) continue
    for (const name of names) {
      const candidate = join(directory, name)
      if (!existsSync(candidate)) continue
      try {
        return realpathSync(candidate)
      } catch {
        return candidate
      }
    }
  }
  return ''
}
