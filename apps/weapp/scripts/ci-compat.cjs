// miniprogram-ci probes the IDE's localStorage; Node's Web Storage is unrelated.
// Preload in the compiler, its child processes and Workers, including Node 20.
Object.defineProperty(globalThis, 'localStorage', { value: undefined, configurable: true })
const preload = `--require=${JSON.stringify(__filename)}`
const options = process.env.NODE_OPTIONS || ''
if (!options.includes(preload)) process.env.NODE_OPTIONS = `${options} ${preload}`.trim()
