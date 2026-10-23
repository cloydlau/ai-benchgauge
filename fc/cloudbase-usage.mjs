import { readBounded } from './arena-dataset.mjs';

export const cloudbaseKind = 'cloudbaseUsage';
export const cloudbaseInterval = 24 * 60 * 60 * 1000;
export const cloudbaseSource = 'https://docs.cloudbase.net/ai/announcement/model-token-volume';

// Exact published family labels, scoped to CloudBase. Never infer a version,
// developer or license from a substring, hosting provider or a similar model.
const families = new Map([
  ['DeepSeek-V4-Flash', ['deepseek', 'DeepSeek V4 Flash', 'deepseek/deepseek-v4-flash']],
  ['DeepSeek-V4-Pro', ['deepseek', 'DeepSeek V4 Pro', 'deepseek/deepseek-v4-pro']],
  ['Hunyuan Hy3', ['tencent', 'Hunyuan Hy3', 'tencent/hy3']],
  ['Hy4-preview', ['tencent', 'Hunyuan Hy4 Preview', 'tencent/hy4-preview']],
  ['GLM-5.3', ['zai', 'GLM 5.3', 'zhipuai/glm-5.3']],
  ['GLM-5.3-Flash', ['zai', 'GLM 5.3 Flash', 'zhipuai/glm-5.3-flash']],
  ['GLM-5.2', ['zai', 'GLM 5.2', 'zhipuai/glm-5.2']],
  ['Kimi-K3', ['moonshotai', 'Kimi K3', 'moonshotai/kimi-k3']],
  ['MiniMax-M3', ['minimax', 'MiniMax M3', 'minimax/minimax-m3']],
]);
const plain = value => value.replace(/<!--.*?-->/gs, '').replace(/<[^>]*>/g, '').trim();

export function parseCloudBaseUsage(html, { now = Date.now() } = {}) {
  if (typeof html !== 'string' || html.length > 2 * 1024 * 1024
    || !html.includes('输入 Token 与输出 Token 之和，含缓存命中') || !html.includes('北京时间')) throw new Error('Invalid CloudBase methodology');
  // Only the token figure's cumulative legend, never the request-count figure
  // or an average of normalized daily percentages. No upstream JS is executed.
  const figures = [...html.matchAll(/<figure\b[^>]*aria-label="云开发 AI 模型 Token 用量分布图"[^>]*>([\s\S]*?)<\/figure>/g)];
  if (figures.length !== 1) throw new Error('Missing CloudBase token figure');
  const figure = figures[0][1];
  const days = /class="mtv__range"[^>]*>([\s\S]*?)<\/span>/.exec(figure);
  const count = Number(days && /^(\d+)\s*个统计日$/.exec(plain(days[1]))?.[1]);
  if (!Number.isInteger(count) || count < 1 || count > 366) throw new Error('Invalid CloudBase sample period');
  const legends = [...figure.matchAll(/<ol\b[^>]*class="mtv__legend"[^>]*>([\s\S]*?)<\/ol>/g)];
  if (legends.length !== 1) throw new Error('Invalid CloudBase legend');
  const rows = [...legends[0][1].matchAll(/<li\b[^>]*class="mtv__legendItem"[^>]*>([\s\S]*?)<\/li>/g)].map(match => {
    const name = plain(/class="mtv__legendName"[^>]*>([\s\S]*?)<\/span>/.exec(match[1])?.[1] ?? '');
    const raw = plain(/class="mtv__legendPct"[^>]*>([\s\S]*?)<\/span>/.exec(match[1])?.[1] ?? '');
    if (!name || name.length > 128 || /[<>&\x00-\x1f]/.test(name) || !/^\d+(?:\.\d)?%$/.test(raw)) throw new Error('Invalid CloudBase share');
    return { name, score: Number(raw.slice(0, -1)) };
  });
  if (!rows.length || rows.length > 100 || new Set(rows.map(r => r.name)).size !== rows.length
    || rows.some(r => !Number.isFinite(r.score) || r.score < 0 || r.score > 100)
    || !rows.some(r => r.name === 'Other') || Math.abs(rows.reduce((sum, r) => sum + r.score, 0) - 100) > rows.length * 0.05 + 0.001) throw new Error('Incomplete CloudBase shares');
  // Keep the source's published order: rounded ties can have different raw totals.
  const models = rows.filter(r => r.name !== 'Other' && r.score > 0);
  if (!models.length) throw new Error('Empty CloudBase models');
  return { kind: cloudbaseKind, title: 'Tencent CloudBase', fetchedAt: new Date(now).toISOString(),
    // The public legend omits full calendar dates. A fetch is not publication.
    sourceNote: `Source: Tencent CloudBase · ${cloudbaseSource}\nCumulative text-token share across ${count} sampled Beijing-time days; full statistic dates are not published in the legend. Input + output tokens, including cache hits. Model-family aggregation; Other excluded; published rounded shares retained. Company shares sum listed families only. No absolute volumes published.\nTencent retains its rights. No open-data license is stated on the source page; this is not CC BY data.`,
    otherSharePercent: rows.find(r => r.name === 'Other').score,
    entries: models.map((row, index) => {
      const identity = families.get(row.name);
      return { rank: index + 1, name: identity?.[1] ?? row.name, score: row.score,
        modelID: `cloudbase-family:${row.name}`, ...(identity && { organization: identity[0], cloudbaseCanonicalID: identity[2] }) };
    }) };
}

export async function loadCloudBaseUsage({ now = Date.now(), fetcher = fetch } = {}) {
  const response = await fetcher(cloudbaseSource, { signal: AbortSignal.timeout(18000), redirect: 'error', headers: { Accept: 'text/html' } });
  return parseCloudBaseUsage((await readBounded(response, 2 * 1024 * 1024)).toString('utf8'), { now });
}
