import { ci } from './calmmit.mjs'
import { repositoryURL } from '../apps/weapp/src/core/catalog.js'

const { collectContributorCircles, renderContributorCirclesSVG } = await ci.load('contributor-circles')

export function contributorCircles(repository) {
  return collectContributorCircles(repository, {
    repositoryURL,
    avatars: { 'github-actions[bot]': { file: 'assets/logos/github.png', monochrome: true } },
  })
}

// Image exports and interactive clients consume the same Calmmit snapshot.
export function contributorCirclesSVG(repository, options = {}) {
  return renderContributorCirclesSVG(contributorCircles(repository), { repository, ...options })
}
