import { readFileSync, readdirSync, realpathSync } from 'node:fs'
import { resolve, dirname } from 'node:path'
import { createRequire } from 'node:module'
import { fileURLToPath } from 'node:url'
import { defineConfig } from 'weapp-vite/config'
import { VantResolver } from 'weapp-vite/auto-import-components/resolvers'
import { engineeringInvestment } from './scripts/engineering-investment.mjs'

const root = fileURLToPath(new URL('../..', import.meta.url))
// The native clients remain the authority for the shared-service address.
const swift = readFileSync(resolve(root, 'Sources/LeaderboardKit/SharedLeaderboardConfiguration.swift'), 'utf8')
const endpoint = process.env.VITE_BENCHGAUGE_SHARED_ENDPOINT
  || swift.match(/bundledEndpoint: String\? = "([^"]+)"/)?.[1]
const address = new URL(endpoint)
if (address.protocol !== 'https:' || address.username || address.password || address.search || address.hash) throw new Error('A valid HTTPS shared endpoint is required')
const version = JSON.parse(readFileSync(resolve(root, 'config/app.json'))).version
const notices = [
  ['Vue Mini', '@vue-mini/core'], ['Vant Weapp', '@vant/weapp'], ['Tailwind CSS', 'tailwindcss'], ['fflate', 'fflate'],
].map(([name, packageName]) => ({ name, license: readFileSync(new URL(`node_modules/${packageName}/LICENSE`, import.meta.url), 'utf8') }))
notices.push({ name: 'Lucide Icons', licenseName: 'ISC', license: readFileSync(new URL('assets/openness/LICENSE', import.meta.url), 'utf8') })
notices.push({ name: 'flag-icons', license: readFileSync(new URL('assets/flags/LICENSE', import.meta.url), 'utf8') })
notices.push({ name: 'Slide Xiaxing / BenchGauge Calligraphy', licenseName: 'SIL OFL 1.1',
  license: readFileSync(resolve(root, 'Sources/LeaderboardKit/Resources/Fonts/SlideFont-OFL.txt'), 'utf8') })
const coreRequire = createRequire(realpathSync(fileURLToPath(new URL('node_modules/@vue-mini/core/package.json', import.meta.url))))
const reactivityPackage = coreRequire.resolve('@vue/reactivity/package.json')
const sharedPackage = createRequire(reactivityPackage).resolve('@vue/shared/package.json')
for (const [name, manifest] of [['Vue Reactivity', reactivityPackage], ['Vue Shared', sharedPackage]]) {
  notices.push({ name, license: readFileSync(resolve(dirname(manifest), 'LICENSE'), 'utf8') })
}

// Neutral public metadata, following Watrek's notice presentation. Original
// copyrights, permission terms and disclaimers remain byte-for-byte intact.
const publishedNotices = notices.map((item, index) => {
  const number = String(index + 1).padStart(2, '0')
  return { id: `third-party-${number}`, number, licenseName: item.licenseName || 'MIT', license: item.license }
})

export default defineConfig({
  build: { target: 'es2019' },
  define: { __SHARED_ENDPOINT__: JSON.stringify(endpoint.replace(/\/$/, '')), __APP_VERSION__: JSON.stringify(version),
    __MIT_LICENSE__: JSON.stringify(readFileSync(resolve(root, 'LICENSE'), 'utf8')),
    __THIRD_PARTY_NOTICES__: JSON.stringify(publishedNotices),
    __ENGINEERING_INVESTMENT__: JSON.stringify(engineeringInvestment(process.env.BENCHGAUGE_INVESTMENT_ROOT || root)) },
  server: { watch: { usePolling: true, interval: 400, ignored: ['**/dist/**', '**/node_modules/**'] } },
  weapp: {
    srcRoot: './src',
    // The post-build Vant pruning removes unused components from this output.
    // Recopy dependencies so later builds can use newly introduced components.
    npm: { cache: false },
    chunks: { sharedStrategy: 'duplicate', sharedMode: 'inline' },
    hmr: { sharedChunks: 'full' },
    autoImportComponents: { resolvers: [VantResolver()] },
  },
  plugins: [
    {
      name: 'benchgauge-existing-assets',
      generateBundle() {
        const emit = (fileName, path) => this.emitFile({ type: 'asset', fileName, source: readFileSync(path) })
        emit('assets/header-logo.png', resolve(root, 'assets/brand/header-logo.png'))
        emit('assets/header-logo-dark.png', resolve(root, 'assets/brand/header-logo-dark.png'))
        for (const name of readdirSync(new URL('assets/brand-glyphs/', import.meta.url)).filter(name => name.endsWith('.svg'))) {
          emit(`assets/brand-glyphs/${name}`, new URL(`assets/brand-glyphs/${name}`, import.meta.url))
        }
        emit('assets/brand-glyphs/LICENSE.txt', resolve(root, 'Sources/LeaderboardKit/Resources/Fonts/SlideFont-OFL.txt'))
        for (const name of readdirSync(resolve(root, 'assets/logos')).filter(name => name.endsWith('.png'))) {
          emit(`assets/logos/${name}`, resolve(root, 'assets/logos', name))
        }
        for (const name of readdirSync(new URL('assets/openness/', import.meta.url)).filter(name => name.endsWith('.png'))) {
          emit(`assets/openness/${name}`, new URL(`assets/openness/${name}`, import.meta.url))
        }
        emit('assets/openness/LICENSE.txt', new URL('assets/openness/LICENSE', import.meta.url))
        for (const name of readdirSync(new URL('assets/flags/', import.meta.url)).filter(name => name.endsWith('.png'))) {
          emit(`assets/flags/${name}`, new URL(`assets/flags/${name}`, import.meta.url))
        }
        emit('assets/flags/LICENSE.txt', new URL('assets/flags/LICENSE', import.meta.url))
        emit('assets/LICENSE.txt', resolve(root, 'LICENSE'))
      },
    },
  ],
})
