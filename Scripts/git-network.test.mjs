import assert from 'node:assert/strict'
import test from 'node:test'

import { gitProxyArgs, gitProxyValue, proxyUrlsFromScutil } from './git-network.mjs'

const SCUTIL = `
<dictionary> {
  HTTPEnable : 1
  HTTPPort : 7897
  HTTPProxy : 127.0.0.1
  HTTPSEnable : 1
  HTTPSPort : 7897
  HTTPSProxy : 127.0.0.1
  SOCKSEnable : 1
  SOCKSPort : 7897
  SOCKSProxy : 127.0.0.1
}
`

test('reads the macOS HTTPS system proxy', () => {
  assert.deepEqual(proxyUrlsFromScutil(SCUTIL), {
    https: 'http://127.0.0.1:7897',
    http: 'http://127.0.0.1:7897',
    socks: 'socks5://127.0.0.1:7897',
  })
  assert.equal(gitProxyValue({}, SCUTIL), 'http://127.0.0.1:7897')
  assert.deepEqual(gitProxyArgs({}, SCUTIL), ['-c', 'http.proxy=http://127.0.0.1:7897'])
})

test('keeps an explicit proxy instead of the system proxy', () => {
  assert.equal(gitProxyValue({ https_proxy: 'http://127.0.0.1:1' }, SCUTIL), '')
  assert.deepEqual(gitProxyArgs({ ALL_PROXY: 'socks5://127.0.0.1:1' }, SCUTIL), [])
})

test('falls back to SOCKS when HTTP proxies are disabled', () => {
  const text = `
    HTTPEnable : 0
    HTTPSEnable : 0
    SOCKSEnable : 1
    SOCKSProxy : 127.0.0.1
    SOCKSPort : 7897
  `
  assert.equal(gitProxyValue({}, text), 'socks5://127.0.0.1:7897')
})

test('ignores a disabled system proxy', () => {
  assert.equal(gitProxyValue({}, 'HTTPSEnable : 0\nHTTPEnable : 0\nSOCKSEnable : 0\n'), '')
  assert.deepEqual(gitProxyArgs({}, ''), [])
})
