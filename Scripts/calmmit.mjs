import { readFileSync } from 'node:fs'
import { dirname, resolve } from 'node:path'
import { fileURLToPath, pathToFileURL } from 'node:url'

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..')
const config = JSON.parse(readFileSync(resolve(root, 'calmmit.config.json'), 'utf8'))
const library = resolve(root, process.env.CALMMIT_PATH || config.library)
let createClient
try { ({ createClient } = await import(pathToFileURL(resolve(library, 'src/client.mjs')).href)) }
catch (error) { throw new Error(`找不到 Calmmit：${library}。请修改 calmmit.config.json 的 library 或设置 CALMMIT_PATH。`, { cause: error }) }
export const ci = createClient({ root, library })
if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) ci.run()
