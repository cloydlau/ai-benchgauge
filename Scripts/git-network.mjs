// git 不会读取 macOS 系统代理。Clash 只开了系统代理、没导出 https_proxy 时，
// 提交仍能成功，但 git push 访问 GitHub 会被连接重置。

import { spawnSync } from 'node:child_process'

const PROXY_ENV_KEYS = ['https_proxy', 'HTTPS_PROXY', 'http_proxy', 'HTTP_PROXY', 'all_proxy', 'ALL_PROXY']

export function hasExplicitProxy(env = process.env) {
  return PROXY_ENV_KEYS.some((key) => env[key])
}

export function proxyUrlsFromScutil(text) {
  const block = String(text || '')
  const read = (kind) => {
    if (!new RegExp(`^\\s*${kind}Enable\\s*:\\s*1\\s*$`, 'm').test(block)) return ''
    const host = block.match(new RegExp(`^\\s*${kind}Proxy\\s*:\\s*(\\S+)\\s*$`, 'm'))?.[1]
    const port = block.match(new RegExp(`^\\s*${kind}Port\\s*:\\s*(\\d+)\\s*$`, 'm'))?.[1]
    if (!host || !port) return ''
    return `http://${host}:${port}`
  }
  const socksEnabled = /^\s*SOCKSEnable\s*:\s*1\s*$/m.test(block)
  const socksHost = block.match(/^\s*SOCKSProxy\s*:\s*(\S+)\s*$/m)?.[1]
  const socksPort = block.match(/^\s*SOCKSPort\s*:\s*(\d+)\s*$/m)?.[1]
  return {
    https: read('HTTPS'),
    http: read('HTTP'),
    socks: socksEnabled && socksHost && socksPort ? `socks5://${socksHost}:${socksPort}` : '',
  }
}

export function gitProxyValue(env = process.env, scutilText = undefined) {
  if (hasExplicitProxy(env)) return ''
  let text = scutilText
  if (text == null) {
    if (process.platform !== 'darwin') return ''
    const result = spawnSync('scutil', ['--proxy'], { encoding: 'utf8' })
    if (result.status !== 0) return ''
    text = result.stdout || ''
  }
  const urls = proxyUrlsFromScutil(text)
  return urls.https || urls.http || urls.socks || ''
}

export function gitProxyArgs(env = process.env, scutilText = undefined) {
  const proxy = gitProxyValue(env, scutilText)
  return proxy ? ['-c', `http.proxy=${proxy}`] : []
}
