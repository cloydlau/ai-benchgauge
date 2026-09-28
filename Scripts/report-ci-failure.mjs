#!/usr/bin/env node
import { readFileSync } from 'node:fs'
const lines = readFileSync(process.argv[2], 'utf8').replace(/\u001b\[[0-9;]*m/g, '').split('\n')
const focused = new Set()
for (let i = 0; i < lines.length; i++) {
  if (/error:|fatal error|error [A-Z]+\d+|Exception|AssertionError|ERR_|failed|Stack dump|While |Pass Manager|✘|✖|not ok/i.test(lines[i])) {
    for (let j = Math.max(0, i - 1); j <= Math.min(lines.length - 1, i + 3); j++) focused.add(j)
  }
}
const selected = focused.size ? [...focused].sort((a, b) => a - b).map(i => lines[i]) : lines.slice(-160)
const log = [...new Set(selected.map(line => line.slice(0, 1800)))].join('\n').slice(0, 24000)
console.log('::error title=Build verification failed::' + log.replaceAll('%', '%25').replaceAll('\r', '%0D').replaceAll('\n', '%0A'))
