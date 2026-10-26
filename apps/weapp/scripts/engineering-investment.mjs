import { resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import { ci } from '../../../Scripts/calmmit.mjs'

const { collectEngineeringInvestment } = await ci.load('engineering-investment')
const { syncCostRuntime } = await ci.load('cost-runtime')
const root = fileURLToPath(new URL('../../../', import.meta.url))

export function syncInvestmentRuntime({ check = false } = {}) {
  return syncCostRuntime({
    javascript: resolve(root, 'apps/weapp/src/generated/cost-calculation.js'),
    swift: resolve(root, 'apps/ios/UI/CalmmitCostCalculation.generated.swift'),
    check,
  })
}

// Build-time adapters are generated before Vite loads the client module graph.
syncInvestmentRuntime()

export function engineeringInvestment(repository) {
  const stats = collectEngineeringInvestment(repository, {
    buckets: { product: ['Sources/', 'apps/', 'fc/'] },
    excludeExtensions: [], requireUtf8: true,
    excludeDirectories: ['node_modules', 'dist', 'bin', 'obj', 'generated'],
    excludeFiles: ['package-lock.json', 'pnpm-lock.yaml'],
  })
  return { commitCount: stats.commitCount, codeLineCount: stats.codeLineCount }
}
