import { mkdirSync, writeFileSync } from 'node:fs'
import { dirname } from 'node:path'
import { copy, text, languages, desktopDownloadURL, repositoryURL, leaderboardSources } from '../apps/weapp/src/core/catalog.js'
import { engineeringInvestment } from '../apps/weapp/scripts/engineering-investment.mjs'
import { aboutPlatforms } from '../apps/weapp/src/core/about-platforms.js'
import { aboutArtwork } from '../apps/weapp/src/core/about-artwork.js'
import { contributorsContent } from '../apps/weapp/src/core/contributors.js'
import { contributorCircles } from './contributor-circles.mjs'

// Load client calculations after the shared runtime has been synchronized.
const { investmentContent, investmentSchedule } = await import('../apps/weapp/src/core/investment.js')

// Native About uses the mini-program's copy and cost definitions. Monthly
// investment is recalculated on-device; engineering counters are build-time data.
export function iosAboutContent(stats, contributors = null) {
  return {
    desktopDownloadURL, repositoryURL, sources: leaderboardSources, schedule: investmentSchedule,
    languages: Object.fromEntries(languages.map(language => [language, {
      descriptionLines: text(copy.description, language).match(/[^。.]+[。.]?/g).map(line => line.trim()),
      platforms: aboutPlatforms(language),
      artwork: aboutArtwork(language),
      investment: investmentContent(stats, language, { now: investmentSchedule.startedAt }),
      contributors: contributorsContent(contributors, language),
    }])),
  }
}

export function writeIOSAbout(repository, output, stats = engineeringInvestment(repository), contributors = contributorCircles(repository)) {
  mkdirSync(dirname(output), { recursive: true })
  writeFileSync(output, JSON.stringify(iosAboutContent(stats, contributors)) + '\n')
  return output
}
