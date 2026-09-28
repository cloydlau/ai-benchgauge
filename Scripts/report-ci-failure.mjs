#!/usr/bin/env node
import { readFileSync } from 'node:fs'
const log = readFileSync(process.argv[2], 'utf8').split('\n').slice(-160).join('\n').slice(-12000)
console.log('::error title=Build verification failed::' + log.replaceAll('%', '%25').replaceAll('\r', '%0D').replaceAll('\n', '%0A'))
