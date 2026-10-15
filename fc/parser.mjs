import { countryCode } from './countries.mjs';
import { normalizedBrandKey } from './brands.mjs';
// Keep the record selectors aligned with HTMLLeaderboardParser.swift.
// Accept source HTML, never a client-supplied score table or timestamp.
export const sources = Object.freeze({
  artificialAnalysis: ['https://artificialanalysis.ai/evaluations/artificial-analysis-intelligence-index', 'Artificial Analysis Intelligence Index'],
  artificialAnalysisCodingAgent: ['https://artificialanalysis.ai/agents/coding-agents', 'Artificial Analysis Coding Agent Index'],
  arenaText: ['https://arena.ai/leaderboard/text', 'Arena | Text'],
  codeArenaWebDev: ['https://arena.ai/leaderboard/code/webdev', 'Code Arena | WebDev'],
  artificialAnalysisTextToImage: ['https://artificialanalysis.ai/image/leaderboard/text-to-image', 'Artificial Analysis | 文生图'],
  arenaTextToImage: ['https://arena.ai/leaderboard/text-to-image', 'Arena | 文生图'],
  artificialAnalysisTextToVideo: ['https://artificialanalysis.ai/video/leaderboard/text-to-video', 'Artificial Analysis | 文生视频'],
  arenaTextToVideo: ['https://arena.ai/leaderboard/text-to-video', 'Arena | 文生视频'],
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

function logo(path) {
  if (!safeString(path, 2048)) return undefined;
  try {
    const url = new URL(path, 'https://artificialanalysis.ai');
    // Contributions cannot inject arbitrary tracking URLs or local URLs.
    if (url.protocol === 'https:' && !url.username && !url.password
      && (url.hostname === 'artificialanalysis.ai' || url.hostname.endsWith('.artificialanalysis.ai'))) return url.href;
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
  if (!Object.hasOwn(sources, kind) || typeof html !== 'string') throw new Error('Invalid source');
  const text = payload(html);
  const arena = kind === 'codeArenaWebDev' || kind.startsWith('arena');
  const coding = kind === 'artificialAnalysisCodingAgent';
  const intelligence = kind === 'artificialAnalysis';
  const marker = arena ? 'modelDisplayName' : coding ? 'indexScore' : intelligence ? 'intelligenceIndex' : 'formatted';
  const seen = new Set(), rows = [], organizationLogoURLs = {};
  for (const record of objects(text, marker)) {
    const value = arena || coding || intelligence ? record : record.formatted && record.values;
    if (!value || intelligence && value.intelligenceIndexIsEstimated === true) continue;
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
    const modelLogoURL = logo(value.modelLogoURL);
    const openness = modelOpenness(value);
    const creatorCountry = coding ? null : arena ? value.modelOrganizationCountryCode ?? value.modelOrganizationCountry
      : creator?.headquartersCountryCode ?? creator?.countryCode ?? creator?.country?.iso2 ?? creator?.country;
    const code = countryCode(creatorCountry);
    const countryHint = code && organization ? { key: normalizedBrandKey(organization), countryCode: code } : null;
    const organizationWebsite = safeString(arena ? value.modelOrganizationWebsite : creator?.website, 2048);
    if (organization && logoURL) organizationLogoURLs[organization] = logoURL;
    rows.push({ name, score, ...(modelID && { modelID }), ...(organization && { organization }), ...(logoURL && { logoURL }), ...(modelLogoURL && { modelLogoURL }), ...(openness && { openness }), ...(countryHint && { countryHint }), ...(organizationWebsite && { organizationWebsite }) });
  }
  if (rows.length < (coding ? 10 : 20)) throw new Error('Incomplete source data');
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
    ...(Object.keys(organizationLogoURLs).length && { organizationLogoURLs }) };
}
