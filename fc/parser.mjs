import { parse as parseHTML } from 'parse5';
import { parseEpochECI } from './epoch-eci.mjs';
import { countryCode } from './countries.mjs';
import { normalizedBrandKey } from './brands.mjs';
import { arenaRowLogos } from './source-logos.mjs';
// Keep the record selectors aligned with HTMLLeaderboardParser.swift.
// Accept source HTML, never a client-supplied score table or timestamp.
export const sources = Object.freeze({
  cloudbaseUsage: ['https://docs.cloudbase.net/ai/announcement/model-token-volume', 'Tencent Cloud'],
  vercelUsage: ['https://vercel.com/ai-gateway/leaderboards/models', 'Vercel AI Gateway'],
  openRouterUsage: ['https://openrouter.ai/rankings', 'OpenRouter'],
  artificialAnalysis: ['https://artificialanalysis.ai/evaluations/artificial-analysis-intelligence-index', 'Artificial Analysis Intelligence Index'],
  valsSWEbench: ['https://www.vals.ai/benchmarks/swebench', 'Vals AI · SWE-bench Verified'],
  artificialAnalysisCodingAgent: ['https://artificialanalysis.ai/agents/coding-agents', 'Artificial Analysis Coding Agent Index'],
  epochECI: ['https://epoch.ai/data/eci_scores.csv', 'Epoch Capabilities Index'],
  arenaText: ['https://arena.ai/leaderboard/text', 'Arena | Text'],
  arenaTextUncontrolled: ['https://arena.ai/leaderboard/text', 'Arena | Text · Original'],
  codeArenaWebDev: ['https://arena.ai/leaderboard/code/webdev', 'Code Arena | WebDev'],
  codeArenaImageToWebDev: ['https://arena.ai/leaderboard/code/image-to-webdev', 'Code Arena | Image-to-WebDev'],
  artificialAnalysisTextToImage: ['https://artificialanalysis.ai/image/leaderboard/text-to-image', 'Artificial Analysis | 文生图'],
  artificialAnalysisImageEditing: ['https://artificialanalysis.ai/image/leaderboard/editing', 'Artificial Analysis | 图片编辑'],
  arenaTextToImage: ['https://arena.ai/leaderboard/text-to-image', 'Arena | 文生图'],
  arenaImageEditing: ['https://arena.ai/leaderboard/image/image-edit/single-image', 'Arena | 单图编辑'],
  arenaMultiImageEditing: ['https://arena.ai/leaderboard/image/image-edit/multi-image', 'Arena | 多图编辑'],
  artificialAnalysisTextToVideo: ['https://artificialanalysis.ai/video/leaderboard/text-to-video', 'Artificial Analysis | 文生视频'],
  artificialAnalysisImageToVideo: ['https://artificialanalysis.ai/video/leaderboard/image-to-video', 'Artificial Analysis | 图生视频'],
  artificialAnalysisVideoEditing: ['https://artificialanalysis.ai/video/leaderboard/video-editing', 'Artificial Analysis | 视频编辑'],
  artificialAnalysisSpeechProviderVoice: ['https://artificialanalysis.ai/text-to-speech/leaderboard/provider-voice', 'Artificial Analysis | 文字转语音 · 原生声音'],
  artificialAnalysisSpeechControlledVoice: ['https://artificialanalysis.ai/text-to-speech/leaderboard/controlled-voice', 'Artificial Analysis | 文字转语音 · 受控声音'],
  artificialAnalysisSpeechAgent: ['https://artificialanalysis.ai/speech-to-speech/arena', 'Artificial Analysis | 语音对话'],
  artificialAnalysisSpeechToText: ['https://artificialanalysis.ai/speech-to-text/non-streaming', 'Artificial Analysis | 语音转文字 · 非流式'],
  artificialAnalysisSpeechToTextStreaming: ['https://artificialanalysis.ai/speech-to-text/streaming', 'Artificial Analysis | 语音转文字 · 流式'],
  arenaTextToVideo: ['https://arena.ai/leaderboard/text-to-video', 'Arena | 文生视频'],
  arenaImageToVideo: ['https://arena.ai/leaderboard/video/image-to-video', 'Arena | 图生视频'],
  arenaVideoEditing: ['https://arena.ai/leaderboard/video/video-edit', 'Arena | 视频编辑'],
});

function unescape(value) {
  return value.replace(/\\(["\\/nrt])/g, (_, c) => ({ n: '\n', r: '\r', t: '\t' }[c] ?? c));
}

function payload(html) {
  const result = [];
  const opener = 'self.__next_f.push([1,"';
  let from = 0;
  while ((from = html.indexOf(opener, from)) >= 0) {
    const start = from + opener.length;
    let end = start, escaped = false;
    for (; end < html.length; end++) {
      const c = html[end];
      if (escaped) escaped = false;
      else if (c === '\\') escaped = true;
      else if (c === '"') break;
    }
    if (end < html.length) result.push(unescape(html.slice(start, end)));
    from = end + 1;
  }
  return result.join('\n');
}

function objects(text, marker) {
  const stack = [], records = [];
  let quoted = false, escaped = false;
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (quoted) {
      if (escaped) escaped = false;
      else if (c === '\\') escaped = true;
      else if (c === '"') quoted = false;
    } else if (c === '"') quoted = true;
    else if (c === '{') stack.push(i);
    else if (c === '}' && stack.length) {
      const snippet = text.slice(stack.pop(), i + 1);
      if (snippet.includes(marker)) {
        try { records.push(JSON.parse(snippet)); }
        catch { try { records.push(JSON.parse(unescape(snippet))); } catch { /* RSC framing is not JSON. */ } }
      }
    }
  }
  return records;
}

function safeString(value, maximum = 256) {
  return typeof value === 'string' && value.length > 0 && value.length <= maximum
    && !/[\x00-\x1f\x7f]/.test(value) ? value : undefined;
}

function logo(path, arena = false) {
  if (!safeString(path, 2048)) return undefined;
  try {
    const url = new URL(path, arena ? 'https://arena.ai' : 'https://artificialanalysis.ai');
    // Contributions cannot inject arbitrary tracking URLs or local URLs.
    if (url.protocol === 'https:' && !url.username && !url.password
      && !url.port && (arena ? url.hostname === 'arena.ai' && url.pathname.startsWith('/images/models/')
        : url.hostname === 'artificialanalysis.ai')) return url.href;
  } catch { /* Optional logo. */ }
}

// Source-declared public-weight licenses; restrictive licenses are included.
const openLicenses = new Set(["mit", "modifiedmit", "apache20", "kimik3license", "minimaxcommunitylicense", "openmdw11", "tencenthunyuancommunity", "gemma", "nvidiaopenmodel", "deepseek", "ccbync40", "nvidiaopen", "llama31community", "nvidia", "llama4", "llama", "qwen", "llama33", "mistralresearch", "nexusflow", "mrl", "llama31", "gemmalicense", "jambaopen", "llama3community", "deepseeklicense", "qianwenlicense", "dbrxlicense", "llama2community", "yilicense", "ai2impactlowrisk", "noncommercial", "llama32", "ccbyncsa40", "falcon180btiilicense", "qwencommunity10", "qwenresearch", "ideogramopenmodel", "fluxnoncommerciallicense", "krea2communitylicense", "open", "flux1devnoncommerciallicense", "minimaxh3communitylicenseagreement", "ltx2communitylicenseagreement"]);
export function modelOpenness(value) {
  if (typeof value.isOpenWeights === 'boolean') return value.isOpenWeights ? 'open' : 'closed';
  if (value.openWeightsUrl === null) return 'closed';
  if (typeof value.openWeightsUrl === 'string') {
    try { const url = new URL(value.openWeightsUrl); if (['http:', 'https:'].includes(url.protocol) && url.hostname) return 'open'; }
    catch { /* Missing or malformed metadata is not a closed-source claim. */ }
  }
  if (typeof value.license !== 'string') return undefined;
  const key = value.license.toLowerCase().replace(/[^\p{L}\p{N}]/gu, '');
  if (key === 'proprietary') return 'closed';
  return openLicenses.has(key) ? 'open' : undefined;
}

export function parseBoard(kind, html, now) {
  if (kind === 'openRouterUsage' || kind === 'vercelUsage' || kind === 'cloudbaseUsage') throw new Error('Usage requires the official Data API');
  if (!Object.hasOwn(sources, kind) || typeof html !== 'string') throw new Error('Invalid source');
  if (kind === 'epochECI') return parseEpochECI(html, now);
  if (kind === 'valsSWEbench') return parseVals(html, now);
  if (kind === 'artificialAnalysisSpeechAgent') return parseSpeechAgent(html, now);
  if (kind === 'artificialAnalysisSpeechToText' || kind === 'artificialAnalysisSpeechToTextStreaming') return parseSpeechToText(kind, html, now);
  const text = payload(html);
  const arena = kind.startsWith('codeArena') || kind.startsWith('arena');
  const coding = kind === 'artificialAnalysisCodingAgent';
  const intelligence = kind === 'artificialAnalysis';
  const marker = arena ? 'modelDisplayName' : coding ? 'indexScore' : intelligence ? 'intelligenceIndex' : 'formatted';
  const seen = new Set(), rows = [], organizationLogoURLs = Object.create(null);
  const mediaVariant = ['artificialAnalysisImageEditing', 'artificialAnalysisImageToVideo', 'artificialAnalysisVideoEditing', 'artificialAnalysisSpeechProviderVoice', 'artificialAnalysisSpeechControlledVoice'].includes(kind);
  let lastMediaRank = 0;
  for (const record of objects(text, marker)) {
    const value = arena || coding || intelligence ? record : record.formatted && record.values;
    if (!value || intelligence && value.intelligenceIndexIsEstimated === true) continue;
    // AA embeds additional boards after the default board. Do not merge their
    // rows into the selected ranking when the source rank starts over.
    if (mediaVariant) {
      const rank = record.formatted.rank;
      if (!Number.isInteger(rank)) throw new Error('Invalid source rank');
      if (rank <= lastMediaRank) break;
      if (rank !== lastMediaRank + 1) throw new Error('Incomplete source data');
      lastMediaRank = rank;
    }
    const name = safeString(arena ? value.modelDisplayName : coding ? value.displayLabel : value.name);
    const score = arena ? value.rating : coding ? value.indexScore * 100 : intelligence ? value.intelligenceIndex : value.elo;
    const modelID = safeString(arena ? value.modelKey : coding ? value.hostModelSlug : intelligence ? value.slug : value.id);
    const creator = coding ? value.display?.creator : value.creator;
    const organization = safeString(arena ? value.modelOrganization : coding ? creator?.agent : creator?.name);
    if (!name || !Number.isFinite(score) || Math.abs(score) > 100000) continue;
    const key = arena || intelligence ? `${name}|${score}` : coding ? name : modelID ?? name;
    if (seen.has(key)) continue;
    seen.add(key);
    const logoURL = logo(creator?.logo);
    const modelLogoURL = logo(value.modelLogoURL, arena);
    const openness = modelOpenness(value);
    const creatorCountry = coding ? null : arena ? value.modelOrganizationCountryCode ?? value.modelOrganizationCountry
      : creator?.headquartersCountryCode ?? creator?.countryCode ?? creator?.country?.iso2 ?? creator?.country;
    const code = countryCode(creatorCountry);
    const countryHint = code && organization ? { key: normalizedBrandKey(organization), countryCode: code } : null;
    const organizationWebsite = safeString(arena ? value.modelOrganizationWebsite : creator?.website, 2048);
    if (organization && logoURL) organizationLogoURLs[organization] = logoURL;
    // AA image quotes are per 1,000 images; video quotes remain per minute.
    // General/coding costs use their respective source-provided task metrics.
    const taskCostUSD = coding ? value.mean?.costUsd : intelligence ? value.intelligenceIndexCostPerTask?.cost?.total
      : ['artificialAnalysisTextToImage', 'artificialAnalysisImageEditing'].includes(kind) && typeof value.pricePer1kImages === 'number' ? value.pricePer1kImages / 1000
      : ['artificialAnalysisTextToVideo', 'artificialAnalysisImageToVideo', 'artificialAnalysisVideoEditing'].includes(kind) ? value.pricePerMinute : undefined;
    const speed = coding ? value.mean?.agentWallTimeSec : intelligence ? value.timescaleData?.medianOutputSpeed : undefined;
    rows.push({ name, score, ...(typeof speed === 'number' && Number.isFinite(speed) && speed > 0 && { speed }), ...(typeof taskCostUSD === 'number' && Number.isFinite(taskCostUSD) && taskCostUSD >= 0 && { taskCostUSD }), ...(modelID && { modelID }), ...(organization && { organization }), ...(logoURL && { logoURL }), ...(modelLogoURL && { modelLogoURL }), ...(openness && { openness }), ...(countryHint && { countryHint }), ...(organizationWebsite && { organizationWebsite }) });
  }
  if (rows.length < (coding || kind === 'artificialAnalysisVideoEditing' ? 10 : 20)) throw new Error('Incomplete source data');
  const organizationLogoSVGs = Object.create(null);
  if (arena) {
    const rowLogos = arenaRowLogos(html, new Set(rows.map(row => row.name)));
    for (const row of rows) {
      const mark = rowLogos.get(row.name);
      if (!mark) continue;
      if (mark.svg) {
        if (row.organization) organizationLogoSVGs[row.organization] ??= mark.svg;
        else row.modelLogoSVG = mark.svg;
      } else {
        const address = logo(mark.url, true);
        if (!address) continue;
        if (row.organization) {
          row.logoURL = address; organizationLogoURLs[row.organization] ??= address;
        } else row.modelLogoURL ??= address;
      }
    }
  }
  rows.sort((a, b) => b.score - a.score || (a.name.normalize('NFC') < b.name.normalize('NFC') ? -1 : 1));
  const dates = [];
  const dateKey = arena ? 'voteCutoffISOString' : 'materializedAt';
  // Read the decoded RSC stream, which also decodes escaped source timestamps.
  const expression = new RegExp(`"${dateKey}"\\s*:\\s*"([^"\\n]+)"`, 'g');
  for (const match of text.matchAll(expression)) {
    const date = Date.parse(match[1]);
    if (Number.isFinite(date)) dates.push(date);
  }
  const sourceDate = arena ? dates[0] : dates.length ? Math.max(...dates) : undefined;
  if (sourceDate > now + 300000) throw new Error('Future source data');
  const version = intelligence ? html.match(/<title>[^<]*?(v[0-9]+(?:\.[0-9]+)*)/)?.[1]
    : coding ? html.match(/Artificial Analysis Coding Agent Index (v[0-9]+(?:\.[0-9]+)*)/)?.[1] : undefined;
  return { kind, title: sources[kind][1], fetchedAt: new Date(now).toISOString(),
    ...(sourceDate !== undefined && { sourceUpdatedAt: new Date(sourceDate).toISOString() }),
    ...(version && { sourceNote: version }),
    entries: rows.map((row, index) => ({ rank: index + 1, ...row })),
    ...(Object.keys(organizationLogoURLs).length && { organizationLogoURLs }),
    ...(Object.keys(organizationLogoSVGs).length && { organizationLogoSVGs }) };
}

// These are provider/model measurements, not human-vote Elo. WER is a
// fraction in the source; display as a percentage and rank lower values first.
function parseSpeechToText(kind, html, now) {
  const key = kind === 'artificialAnalysisSpeechToTextStreaming' ? 'aaWerStreamingIndex' : 'aaWerIndex';
  const seen = new Set(), rows = [];
  for (const value of objects(payload(html), key)) {
    if (!value.model || !value.host) continue;
    const id = safeString(value.id), name = safeString(value.displayLabel ?? value.displayName ?? value.name);
    const rate = value[key], organization = safeString(value.host.name);
    if (!id || !name || typeof rate !== 'number' || !Number.isFinite(rate) || rate < 0 || rate > 1 || seen.has(id)) continue;
    seen.add(id);
    const logoURL = logo(value.logo), openness = typeof value.model.openWeights === 'boolean' ? (value.model.openWeights ? 'open' : 'closed') : undefined;
    rows.push({ name, modelID: id, score: rate * 100, ...(organization && { organization }), ...(logoURL && { logoURL }), ...(openness && { openness }) });
  }
  if (rows.length < 20) throw new Error('Incomplete speech-to-text ranking');
  rows.sort((a, b) => a.score - b.score || a.name.localeCompare(b.name, 'en'));
  return { kind, title: sources[kind][1], fetchedAt: new Date(now).toISOString(), entries: rows.map((row, i) => ({ rank: i + 1, ...row })) };
}

// Speech Agent embeds separate overall, agentic and non-agentic results.
// Select only the published overall slice and retain its source ranks.
function parseSpeechAgent(html, now) {
  const rows = [], ids = new Set(), ranks = new Set();
  for (const value of objects(payload(html), 'stsHostModelId')) {
    if (value.sliceKey !== 'overall') continue;
    const name = safeString(value.name), modelID = safeString(value.id);
    const organization = safeString(value.creatorName), rank = value.rank, score = value.elo;
    if (!name || !modelID || !Number.isInteger(rank) || rank < 1 || !Number.isFinite(score)
      || Math.abs(score) > 100000 || ids.has(modelID) || ranks.has(rank)) throw new Error('Invalid speech agent ranking');
    ids.add(modelID); ranks.add(rank);
    const logoURL = logo(value.logo);
    rows.push({ rank, name, score, modelID, ...(organization && { organization }), ...(logoURL && { logoURL }) });
  }
  rows.sort((a, b) => a.rank - b.rank);
  if (rows.length < 20 || rows.some((row, i) => row.rank !== i + 1 || (i && row.score > rows[i - 1].score))) throw new Error('Incomplete speech agent ranking');
  return { kind: 'artificialAnalysisSpeechAgent', title: sources.artificialAnalysisSpeechAgent[1],
    fetchedAt: new Date(now).toISOString(), entries: rows };
}

// Vals publishes one row per model and harness. Preserve the source order and variants.
function parseVals(html, now) {
  if (!html.includes('Archived Benchmark')) throw new Error('Missing Vals archive notice');
  const dateMatch = html.match(/Updated\s+(\d{1,2})\/(\d{1,2})\/(\d{4})/);
  if (!dateMatch) throw new Error('Missing Vals source date');
  const sourceDate = Date.UTC(+dateMatch[3], +dateMatch[1] - 1, +dateMatch[2]);
  if (!Number.isFinite(sourceDate) || sourceDate > now + 300000) throw new Error('Invalid Vals date');
  const doc = parseHTML(html);
  const children = node => node.childNodes ?? [];
  const walk = function* (node) { yield node; for (const child of children(node)) yield* walk(child); };
  const text = node => [...walk(node)].filter(n => n.nodeName === '#text').map(n => n.value).join('').trim();
  const table = [...walk(doc)].find(n => n.tagName === 'table' && n.attrs?.some(a => a.name === 'aria-labelledby' && a.value === 'benchmark-leaderboard-title'));
  if (!table) throw new Error('Missing Vals leaderboard');
  const trs = [...walk(table)].filter(n => n.tagName === 'tr');
  const header = children(trs[0] ?? {}).filter(n => n.tagName === 'th').map(text).join('|');
  if (header !== 'Rank|Model|Harness|Score|Cost / Test|Tokens / Test|Duration / Test') throw new Error('Unexpected Vals columns');
  const entries = [];
  for (const tr of trs.slice(1)) {
    const cells = children(tr).filter(n => n.tagName === 'td' || n.tagName === 'th');
    if (cells.length !== 7) throw new Error('Malformed Vals row');
    const [rankText, model, harness, scoreText, costText, , duration] = cells.map(text);
    const rank = Number(rankText), score = Number(scoreText.replace(/%$/, ''));
    if (rank !== entries.length + 1 || !model || !harness || !/^\d+(?:\.\d+)?%$/.test(scoreText) || score > 100) throw new Error('Invalid Vals row');
    const anchor = [...walk(cells[1])].find(n => n.tagName === 'a');
    const slug = anchor?.attrs?.find(a => a.name === 'href')?.value?.match(/^\/models\/([a-zA-Z0-9_.-]+)$/)?.[1];
    if (!slug) throw new Error('Invalid Vals model link');
    const cost = /^\$\d+(?:\.\d+)?$/.test(costText) ? Number(costText.slice(1)) : undefined;
    const time = duration.match(/^(?:(\d+)h)?(?:(\d+)m)?(?:(\d+(?:\.\d+)?)s)?$/);
    const speed = time && (time[1] || time[2] || time[3]) ? (+time[1] || 0) * 3600 + (+time[2] || 0) * 60 + (+time[3] || 0) : undefined;
    const organization = slug.includes('_') ? slug.split('_')[0] : undefined;
    entries.push({ rank, name: `${model} · ${harness}`, score, modelID: `vals:${slug}:${harness}`, ...(organization && { organization }), ...(cost !== undefined && { taskCostUSD: cost }), ...(speed > 0 && { speed }) });
  }
  if (entries.length < 20) throw new Error('Incomplete Vals source data');
  return { kind: 'valsSWEbench', title: sources.valsSWEbench[1], fetchedAt: new Date(now).toISOString(), sourceUpdatedAt: new Date(sourceDate).toISOString(), sourceNote: 'Archived · SWE-bench Verified', entries };
}
