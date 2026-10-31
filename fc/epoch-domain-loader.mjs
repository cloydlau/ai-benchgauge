import { parseEpochCyber, parseEpochDomain } from './epoch-domain-fit.mjs';
import { parseEpochECI } from './epoch-eci.mjs';

// Verified against Epoch's public presets on 2026-10-31. Fail closed if a
// benchmark disappears from the official parameter file; review changes to
// the upstream preset before updating these names.
export const epochDomainPresets = Object.freeze({
  epochMathECI: Object.freeze(['GSM8K', 'MATH level 5', 'OTIS Mock AIME 2024-2025', 'ProofBench', 'FrontierMath-Tiers-1-3-v2-Private', 'FrontierMath-Tier-4-v2-Private']),
  epochSoftwareECI: Object.freeze(['MirrorCode', 'Terminal Bench', 'Aider polyglot', 'Cybench', 'WeirdML', 'WeirdML v3', 'FrontierSWE', 'GSO-Bench', 'ExploitBench', 'PostTrainBench', 'FrontierCode', 'Surface Evolver Bench']),
});
export const isEpochDomain = kind => kind === 'epochCyberECI' || Object.hasOwn(epochDomainPresets, kind);
export const epochAcquisitionKinds = kind => kind === 'epochCyberECI' ? [kind] : Object.keys(epochDomainPresets);
export async function loadEpochDomain(kind, { now = Date.now(), fetcher = fetch, includeRelated = false } = {}) {
  if (!isEpochDomain(kind)) throw new Error('Unknown Epoch domain');
  const path = kind === 'epochCyberECI' ? 'cyber/' : '';
  const filenames = ['eci_scores.csv', 'processed_data_for_eci.csv', 'edi_scores.csv'];
  const parts = await Promise.all(filenames.map(async name => {
    let response;
    // Keep retries inside one coordinated acquisition and the function's budget.
    for (let attempt = 0; attempt < 3; attempt++) {
      try {
        response = await fetcher(`https://epoch.ai/data/${path}${name}`, { signal: AbortSignal.timeout(6000), redirect: 'error' });
      } catch (error) {
        if (attempt === 2) throw error;
      }
      if (response?.ok) break;
      if (response && ![408, 429].includes(response.status) && response.status < 500) throw new Error('Epoch source unavailable');
      if (attempt === 2) throw new Error('Epoch source unavailable');
      await new Promise(resolve => setTimeout(resolve, 200 * (attempt + 1)));
      response = undefined;
    }
    const length = Number(response.headers.get('content-length'));
    if (Number.isFinite(length) && length > 8_000_000) throw new Error('Epoch source too large');
    const text = await response.text();
    if (text.length > 8_000_000) throw new Error('Epoch source too large');
    return text;
  }));
  const parse = candidate => candidate === 'epochCyberECI' ? parseEpochCyber(...parts, now)
    : parseEpochDomain(candidate, ...parts, epochDomainPresets[candidate], now);
  const board = parse(kind);
  if (!includeRelated) return board;
  const relatedBoards = [];
  for (const candidate of epochAcquisitionKinds(kind).filter(candidate => candidate !== kind)) {
    try { relatedBoards.push(parse(candidate)); } catch { /* A missing preset must not invalidate the other domain. */ }
  }
  if (kind !== 'epochCyberECI') relatedBoards.push(parseEpochECI(parts[0], now));
  return { ...board, relatedBoards };
}
