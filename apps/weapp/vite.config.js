import { readFileSync, readdirSync, realpathSync } from 'node:fs'
import { resolve, dirname } from 'node:path'
import { createRequire } from 'node:module'
import { fileURLToPath } from 'node:url'
import { defineConfig } from 'weapp-vite/config'
import { VantResolver } from 'weapp-vite/auto-import-components/resolvers'
import sourceThemes from '../../Sources/LeaderboardKit/Resources/SourceTabThemes.json' with { type: 'json' }
import sharp from 'sharp'
import { engineeringInvestment } from './scripts/engineering-investment.mjs'
import { contributorCircles } from '../../Scripts/contributor-circles.mjs'
import { createAutoVersion } from './scripts/version.mjs'
import { renderSourceLogos, renderPlatformIcons } from '../../Scripts/source-logos.mjs'
import { aboutArtworkFile } from './src/core/about-artwork.js'

const root = fileURLToPath(new URL('../..', import.meta.url))
// The native clients remain the authority for the shared-service address.
const swift = readFileSync(resolve(root, 'Sources/LeaderboardKit/SharedLeaderboardConfiguration.swift'), 'utf8')
const endpoint = process.env.VITE_BENCHGAUGE_SHARED_ENDPOINT
  || swift.match(/bundledEndpoint: String\? = "([^"]+)"/)?.[1]
const address = new URL(endpoint)
if (address.protocol !== 'https:' || address.username || address.password || address.search || address.hash) throw new Error('A valid HTTPS shared endpoint is required')
const version = process.env.MP_VERSION || createAutoVersion()
const notices = [
  ['Vue Mini', '@vue-mini/core'], ['Vant Weapp', '@vant/weapp'], ['Tailwind CSS', 'tailwindcss'], ['fflate', 'fflate'],
].map(([name, packageName]) => ({ name, license: readFileSync(new URL(`node_modules/${packageName}/LICENSE`, import.meta.url), 'utf8') }))
notices.push({ name: 'Lucide Icons', licenseName: 'ISC', license: readFileSync(new URL('assets/openness/LICENSE', import.meta.url), 'utf8') })
notices.push({ name: 'Fluent UI System Color Icons', licenseName: 'MIT',
  license: readFileSync(resolve(root, 'apps/ios/UI/Resources/CategoryIcons/LICENSE.txt'), 'utf8') })
notices.push({ name: 'flag-icons', license: readFileSync(new URL('assets/flags/LICENSE', import.meta.url), 'utf8') })
notices.push({ name: 'Slide Xiaxing / BenchGauge Calligraphy', licenseName: 'SIL OFL 1.1',
  license: readFileSync(resolve(root, 'Sources/LeaderboardKit/Resources/Fonts/SlideFont-OFL.txt'), 'utf8') })
notices.push({ name: 'models.dev', id: 'models-dev', licenseName: 'MIT',
  license: readFileSync(resolve(root, 'fc/models-dev-license.txt'), 'utf8') })
const coreRequire = createRequire(realpathSync(fileURLToPath(new URL('node_modules/@vue-mini/core/package.json', import.meta.url))))
const reactivityPackage = coreRequire.resolve('@vue/reactivity/package.json')
const sharedPackage = createRequire(reactivityPackage).resolve('@vue/shared/package.json')
for (const [name, manifest] of [['Vue Reactivity', reactivityPackage], ['Vue Shared', sharedPackage]]) {
  notices.push({ name, license: readFileSync(resolve(dirname(manifest), 'LICENSE'), 'utf8') })
}
notices.push({ name: 'Source brand marks', id: 'source-marks', licenseName: 'Trademarks',
  license: readFileSync(resolve(root, 'assets/brand/partners/NOTICE.txt'), 'utf8') })

// Neutral public metadata, following Watrek's notice presentation. Original
// copyrights, permission terms and disclaimers remain byte-for-byte intact.
const publishedNotices = notices.map((item, index) => {
  const number = String(index + 1).padStart(2, '0')
  return { id: item.id || `third-party-${number}`, number,
    licenseName: item.licenseName || 'MIT', license: item.license }
})

export default defineConfig({
  build: { target: 'es2019' },
  define: { __SHARED_ENDPOINT__: JSON.stringify(endpoint.replace(/\/$/, '')), __APP_VERSION__: JSON.stringify(version),
    __MIT_LICENSE__: JSON.stringify(readFileSync(resolve(root, 'LICENSE'), 'utf8')),
    __THIRD_PARTY_NOTICES__: JSON.stringify(publishedNotices),
    __ENGINEERING_INVESTMENT__: JSON.stringify(engineeringInvestment(process.env.BENCHGAUGE_INVESTMENT_ROOT || root)),
    __CONTRIBUTOR_CIRCLES__: JSON.stringify(contributorCircles(process.env.BENCHGAUGE_INVESTMENT_ROOT || root)) },
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
      async generateBundle() {
        const emit = (fileName, path) => this.emitFile({ type: 'asset', fileName, source: readFileSync(path) })
        emit('assets/header-logo.png', resolve(root, 'assets/brand/header-logo.png'))
        emit('assets/header-logo-dark.png', resolve(root, 'assets/brand/header-logo-dark.png'))
        // Keep full image dimensions while staying below WeChat's main-package limit.
        this.emitFile({ type: 'asset', fileName: `assets/about/${aboutArtworkFile}`,
          source: await sharp(resolve(root, 'assets/about', aboutArtworkFile)).jpeg({ quality: 86, mozjpeg: true }).toBuffer() })
        for (const { name, source } of [...await renderSourceLogos(sharp), ...await renderPlatformIcons(sharp)]) {
          this.emitFile({ type: 'asset', fileName: `assets/source-logos/${name}`, source })
        }
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
        // Render local template SVGs into platform-safe PNGs; no CSS masks or
        // remote images are needed when the selected source changes.
        const accents = new Set([sourceThemes.fallback, ...sourceThemes.sources]
          .flatMap(source => [source.light.accent, source.dark.accent]))
        for (const name of ['general', 'coding', 'image', 'video', 'usage']) {
          const template = readFileSync(resolve(root, `apps/ios/UI/Resources/CategoryIcons/${name}.svg`), 'utf8')
          for (const accent of accents) {
            const source = await sharp(Buffer.from(template.replaceAll('currentColor', accent))).resize(54, 54).png().toBuffer()
            this.emitFile({ type: 'asset', fileName: `assets/categories/${name}-${accent.slice(1)}.png`, source })
          }
        }
        emit('assets/categories/LICENSE.txt', resolve(root, 'apps/ios/UI/Resources/CategoryIcons/LICENSE.txt'))
        for (const name of readdirSync(new URL('assets/flags/', import.meta.url)).filter(name => name.endsWith('.png'))) {
          emit(`assets/flags/${name}`, new URL(`assets/flags/${name}`, import.meta.url))
        }
        emit('assets/flags/LICENSE.txt', new URL('assets/flags/LICENSE', import.meta.url))
        emit('assets/LICENSE.txt', resolve(root, 'LICENSE'))
      },
    },
  ],
})
