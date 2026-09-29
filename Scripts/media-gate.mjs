// 截图与录屏门禁。
// 屏幕画面会带出账号、余量、时间、内网地址等隐私（demo.gif 就是这么泄露的），
// 所以这类文件不允许模型直接提交：必须由本人审核，并在提交信息里留下审核记录。
// 本地入口在 Scripts/commit.mjs，CI 兜底在 Scripts/media-gate-ci.mjs，两边共用这里的判据。

import { HUMAN } from './commit-identity.mjs'

// 录屏与动图：不论放在哪个目录，都按屏幕内容处理。
const RECORDING_EXTENSIONS = new Set([
  '.gif', '.mov', '.mp4', '.m4v', '.webm', '.avi', '.mkv', '.wmv', '.flv', '.mpg', '.mpeg', '.ogv', '.3gp',
])
// 位图既可能是截图也可能是设计稿，还要看目录和文件名。
const IMAGE_EXTENSIONS = new Set([
  '.png', '.jpg', '.jpeg', '.webp', '.avif', '.heic', '.heif', '.tif', '.tiff', '.bmp',
])
// 已确认是设计稿（矢量导出的图标、logo）的目录，普通位图不需要人工审核。
const ARTWORK_PREFIXES = Object.freeze(['assets/logos/', 'docs/logo/'])
const CAPTURE_NAME_RE = /(screen[\s\-_.]*(shot|capture|grab|recording|cast)|screencap|cleanshot|^frame[\-_.]?\d+\.|截屏|截图|录屏|录影|屏幕快照|屏幕录制)/i
const CAPTURE_DIRECTORY_RE = /(^|\/)(screenshots?|screencaps?|screencasts?|captures?|recordings?|frames?|thumbs?)(\/|$)/i
export const MEDIA_REVIEW_TRAILER = 'Media-Reviewed-By'
const HUMAN_EMAIL = HUMAN.email.toLowerCase()

function normalize(path) {
  return String(path ?? '').trim().replaceAll('\\', '/').replace(/^\.?\//, '')
}

/** 命中判据时返回中文原因，不是截图/录屏则返回空字符串。 */
export function mediaReason(path) {
  const file = normalize(path)
  if (!file) return ''
  const extension = `.${file.split('/').pop().split('.').pop() ?? ''}`.toLowerCase()
  const base = file.split('/').pop()
  if (RECORDING_EXTENSIONS.has(extension)) return extension === '.gif' ? 'GIF 动图' : '录屏视频'
  if (CAPTURE_NAME_RE.test(base)) return '截图文件名'
  if (CAPTURE_DIRECTORY_RE.test(file)) return '截图目录'
  if (IMAGE_EXTENSIONS.has(extension) && !ARTWORK_PREFIXES.some((prefix) => file.startsWith(prefix))) return '位图（可能是截图）'
  return ''
}

export function isMediaPath(path) {
  return mediaReason(path) !== ''
}

export function mediaPaths(paths) {
  return [...new Set([...(paths ?? [])].map(normalize).filter(Boolean))].filter(isMediaPath)
}

export function describeMedia(paths) {
  return mediaPaths(paths).map((path) => `${path}（${mediaReason(path)}）`)
}

/** 解析 git 的 --name-status -z 输出。 */
export function parseNameStatus(output) {
  const tokens = String(output ?? '').split('\0')
  const entries = []
  for (let index = 0; index < tokens.length; index += 1) {
    const status = tokens[index]
    if (!status) continue
    if (status[0] === 'R' || status[0] === 'C') {
      entries.push({ status: status[0], from: tokens[index + 1], path: tokens[index + 2] })
      index += 2
    } else {
      entries.push({ status: status[0], path: tokens[index + 1] })
      index += 1
    }
  }
  return entries
}

// 只有新增和修改会把画面写进历史；删除截图（含撤回已泄露内容）不需要审核。
export function introducedPaths(entries) {
  return (entries ?? []).filter((entry) => entry.path && entry.status !== 'D').map((entry) => entry.path)
}

/** 本人是 author/committer/联合署名时，视为已经人工审核。 */
export function reviewedByIdentity(identity) {
  const emails = [identity?.author?.email, identity?.committer?.email, identity?.coauthor?.email]
  return emails.some((email) => String(email ?? '').toLowerCase() === HUMAN_EMAIL)
}

export function mediaReviewTrailer() {
  return `${MEDIA_REVIEW_TRAILER}: ${HUMAN.name} <${HUMAN.email}>`
}

const TRAILER_RE = new RegExp(`^${MEDIA_REVIEW_TRAILER}:.*${HUMAN.email.replaceAll('+', '\\+').replaceAll('.', '\\.')}`, 'im')

/** CI 侧判据：本人署名，或提交信息里带本人署名的审核记录。 */
export function reviewedCommit({ authorEmail, committerEmail, message } = {}) {
  const emails = [authorEmail, committerEmail].map((email) => String(email ?? '').toLowerCase())
  if (emails.includes(HUMAN_EMAIL)) return true
  return TRAILER_RE.test(String(message ?? ''))
}

/** 审核通过后把记录写进提交信息，CI 才能校验绕过 Scripts/commit.sh 的提交。 */
export function withMediaReview(message, paths) {
  const text = String(message ?? '')
  if (mediaPaths(paths).length === 0 || text.includes(`${MEDIA_REVIEW_TRAILER}:`)) return text
  return `${text.replace(/\s+$/, '')}\n\n${mediaReviewTrailer()}`
}

/**
 * 是否已经人工审核。
 * identityOnly 用于透传 git 参数的场景：那时补不了审核记录，只认本人署名。
 */
export function mediaApproved({ identity, env = process.env, identityOnly = false } = {}) {
  if (reviewedByIdentity(identity)) return true
  return !identityOnly && env.COMMIT_MEDIA_REVIEWED === '1'
}

/**
 * 暂存内容含截图/录屏时要求人工审核，否则抛错中止提交。
 * 审核方式：COMMIT_MEDIA_REVIEWED=1，或 COMMIT_COAUTHOR=1 由本人署名。
 */
export function assertMediaReviewed({ paths, identity, env = process.env, identityOnly = false } = {}) {
  const media = mediaPaths(paths)
  if (media.length === 0) return []
  if (mediaApproved({ identity, env, identityOnly })) return media
  const shown = describeMedia(media).slice(0, 6).join('、')
  const lines = [`涉及截图/录屏，禁止直接提交，需要人工审核：${shown}`]
  if (!identityOnly) lines.push('  确认画面不含账号、余量、时间等隐私后重跑：COMMIT_MEDIA_REVIEWED=1 Scripts/commit.sh …')
  lines.push(identityOnly
    ? '  透传 git 参数时补不了审核记录，只接受本人署名：COMMIT_COAUTHOR=1 Scripts/commit.sh …'
    : '  或以本人身份提交（committer 记为本人）：COMMIT_COAUTHOR=1 Scripts/commit.sh …')
  lines.push('  不需要进版本库就把文件移到已忽略的 work/，或先删掉再提交。')
  throw new Error(lines.join('\n'))
}
