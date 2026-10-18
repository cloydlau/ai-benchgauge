import { mkdirSync, writeFileSync } from 'node:fs'
import { dirname } from 'node:path'
import { copy, text, languages, desktopDownloadURL, leaderboardSources } from '../apps/weapp/src/core/catalog.js'
import { investmentContent, investmentSchedule } from '../apps/weapp/src/core/investment.js'
import { engineeringInvestment } from '../apps/weapp/scripts/engineering-investment.mjs'

// Native About uses the mini-program's copy and cost definitions. Monthly
// investment is recalculated on-device; engineering counters are build-time data.
export function iosAboutContent(stats) {
  return {
    desktopDownloadURL, sources: leaderboardSources, schedule: investmentSchedule,
    languages: Object.fromEntries(languages.map(language => [language, {
      descriptionLines: text(copy.description, language).match(/[^。.]+[。.]?/g).map(line => line.trim()),
      investment: investmentContent(stats, language, { now: investmentSchedule.startedAt }),
    }])),
  }
}

export function writeIOSAbout(repository, output, stats = engineeringInvestment(repository)) {
  mkdirSync(dirname(output), { recursive: true })
  writeFileSync(output, JSON.stringify(iosAboutContent(stats)) + '\n')
  return output
}
