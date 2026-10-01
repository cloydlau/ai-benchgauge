import { ci } from './calmmit.mjs'
const shared = await ci.load('node-executable')
export const nodeOnPath = shared.nodeOnPath
export function nodeExecutable({ env = process.env, ...options } = {}) {
  return shared.nodeExecutable({ ...options, env: { ...env, CALMMIT_NODE: env.BENCHGAUGE_NODE || env.CALMMIT_NODE } })
}
