import { dirname, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import { validateAppConfig } from './app-config.mjs'
try {
  const config = validateAppConfig(resolve(dirname(fileURLToPath(import.meta.url)), '..'), process.argv[2])
  console.log(`Validated shared version ${config.version} and update public key`)
} catch (error) { console.error(error.message); process.exitCode = 1 }
