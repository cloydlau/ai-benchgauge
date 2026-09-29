#!/usr/bin/env node
// CI 兜底：直接用 git commit 能绕过 Scripts/commit.mjs 的截图/录屏门禁，
// 这里复查推送范围内的每个提交，画面类文件必须由本人署名或带审核记录。
//
//   node Scripts/media-gate-ci.mjs                  只检查 HEAD 一个提交
//   node Scripts/media-gate-ci.mjs <base> <head>    检查 base..head
// base 不可解析（新分支、浅克隆、全零 sha）时退回只检查 head。

import { spawnSync } from 'node:child_process'
import { dirname, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import {
  MEDIA_REVIEW_TRAILER, describeMedia, introducedPaths, mediaPaths, parseNameStatus, reviewedCommit,
} from './media-gate.mjs'

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..')

function git(args) {
  const result = spawnSync('git', ['-c', 'core.quotePath=false', ...args], {
    cwd: root, encoding: 'utf8', maxBuffer: 64 * 1024 * 1024,
  })
  if (result.error) throw result.error
  return { status: result.status ?? 1, stdout: result.stdout ?? '' }
}

function commitRef(value) {
  if (!value || /^0+$/.test(value)) return ''
  return git(['rev-parse', '--verify', '--quiet', `${value}^{commit}`]).status === 0 ? value : ''
}

function commitsInRange(base, head) {
  const target = commitRef(head) || 'HEAD'
  const anchor = commitRef(base)
  if (!anchor) {
    if (base) console.warn(`[media-gate] 基线 ${base} 不在本地历史里（新分支或浅克隆），只检查最新提交`)
    return git(['rev-list', '--no-merges', '-n', '1', target]).stdout.split('\n').filter(Boolean)
  }
  return git(['rev-list', '--no-merges', `${anchor}..${target}`]).stdout.split('\n').filter(Boolean)
}

function commitMeta(sha) {
  const shown = git(['show', '-s', '--format=%H%x09%ae%x09%ce%x09%s', sha]).stdout.split('\n')[0] ?? ''
  const [short, authorEmail, committerEmail, subject] = shown.split('\t')
  const message = git(['show', '-s', '--format=%B', sha]).stdout
  return { sha: short || sha, authorEmail, committerEmail, subject, message }
}

function commitMedia(sha) {
  const entries = git(['diff-tree', '-r', '--root', '--no-commit-id', '--name-status', '-z', '--no-renames', sha]).stdout
  return mediaPaths(introducedPaths(parseNameStatus(entries)))
}

const [base, head] = process.argv.slice(2)
const commits = commitsInRange(base, head)
if (commits.length === 0) {
  console.log('[media-gate] 范围内没有提交可检查')
  process.exit(0)
}

let reviewed = 0
const rejected = []
for (const sha of commits) {
  const media = commitMedia(sha)
  if (media.length === 0) continue
  const meta = commitMeta(sha)
  if (reviewedCommit(meta)) {
    reviewed += 1
    console.log(`[media-gate] ${meta.sha.slice(0, 12)} 已人工审核：${describeMedia(media).join('、')}`)
    continue
  }
  rejected.push({ ...meta, media })
}

if (rejected.length === 0) {
  console.log(`[media-gate] 检查 ${commits.length} 个提交，${reviewed} 个含截图/录屏且已人工审核`)
  process.exit(0)
}

console.error(`[media-gate] ${rejected.length} 个提交带截图/录屏，但没有人工审核记录：`)
for (const item of rejected) {
  console.error(`  ${item.sha.slice(0, 12)} ${item.subject}`)
  console.error(`    author=${item.authorEmail} committer=${item.committerEmail}`)
  for (const path of describeMedia(item.media)) console.error(`    - ${path}`)
}
console.error([
  '[media-gate] 屏幕画面可能带出账号、余量、时间等隐私，禁止模型直接提交。',
  `[media-gate] 本人审核后重跑 Scripts/commit.sh（COMMIT_MEDIA_REVIEWED=1 会写入 ${MEDIA_REVIEW_TRAILER} 记录），`,
  '[media-gate] 或用本人身份提交（committer 为 Cloyd Lau）；已经推出去的画面需要改写历史并轮换泄露的凭据。',
].join('\n'))
process.exit(1)
