import { resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import { ci } from './calmmit.mjs'

const { updateNativeDependencies } = await ci.load('dev-native-deps')
export function updateDependencies(options = {}) {
  return updateNativeDependencies({ root: ci.root, ...options })
}
if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url))
  ci.run(['update-deps'])
