import { pathToFileURL } from 'node:url'

export function requireVisualReviewer(environment) {
  const rule = environment?.protection_rules?.find(item => item.type === 'required_reviewers')
  if (environment?.name !== 'native-visual-review' || !rule?.reviewers?.some(item =>
    ['User', 'Team'].includes(item.type) && Number.isInteger(item.reviewer?.id) && item.reviewer.id > 0)) {
    throw new Error('native-visual-review must exist with at least one required human reviewer; release is blocked')
  }
}

export async function checkVisualReviewPolicy({ env = process.env, request = fetch } = {}) {
  if (!/^[\w.-]+\/[\w.-]+$/.test(env.GITHUB_REPOSITORY || '') || !env.GH_TOKEN)
    throw new Error('GITHUB_REPOSITORY and GH_TOKEN are required to verify the visual review gate')
  const response = await request(`https://api.github.com/repos/${env.GITHUB_REPOSITORY}/environments/native-visual-review`, {
    headers: { Accept: 'application/vnd.github+json', Authorization: `Bearer ${env.GH_TOKEN}`,
      'X-GitHub-Api-Version': '2022-11-28' }, signal: AbortSignal.timeout(20_000), redirect: 'error',
  })
  if (!response.ok) throw new Error(`Cannot verify visual review protection (HTTP ${response.status}); release is blocked`)
  requireVisualReviewer(await response.json())
  console.log('Required human reviewer is configured for native-visual-review')
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  checkVisualReviewPolicy().catch(error => { console.error(error.message); process.exitCode = 1 })
}
