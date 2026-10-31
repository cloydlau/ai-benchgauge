import notice from './arena-attribution.json' with { type: 'json' };
import policy from './leaderboard-policy.json' with { type: 'json' };

export const arenaSubsets = Object.freeze({ arenaText: 'text_style_control', arenaTextUncontrolled: 'text', codeArenaWebDev: 'webdev', codeArenaImageToWebDev: 'webdev',
  arenaTextToImage: 'text_to_image', arenaImageEditing: 'image_edit', arenaMultiImageEditing: 'image_edit', arenaTextToVideo: 'text_to_video',
  arenaImageToVideo: 'image_to_video', arenaVideoEditing: 'video_edit' });
export const isArena = kind => Object.hasOwn(arenaSubsets, kind);
// Categories in the same Parquet are one acquisition, with independent rankings.
export const arenaAcquisitionKinds = kind => Object.keys(arenaSubsets).filter(candidate => arenaSubsets[candidate] === arenaSubsets[kind]);
export const arenaCategory = kind => kind === 'arenaMultiImageEditing' ? 'multi_image_edit' : kind === 'codeArenaImageToWebDev' ? 'image_to_webdev' : 'overall';
export const isArenaDataset = board => Boolean(board && isArena(board.kind)
  && board.sourceNote?.includes(notice.sourceURL));
export const arenaDataURL = (kind, revision = 'main') => {
  if (!isArena(kind) || !/^(?:main|[a-f0-9]{40})$/.test(revision)) throw new Error('Invalid Arena dataset source');
  return `${notice.sourceURL}/resolve/${revision}/${arenaSubsets[kind]}/latest-00000-of-00001.parquet`;
};

export function parseArenaRows(kind, rows, { now = Date.now(), revision, classifyLicense = () => undefined } = {}) {
  if (!isArena(kind) || !Array.isArray(rows) || rows.length > 50000 || !/^[a-f0-9]{40}$/.test(revision ?? '')) throw new Error('Invalid dataset');
  const category = arenaCategory(kind);
  const overall = rows.filter(row => row.category === category);
  // `latest` can contain different dates for different categories. Never mix them.
  const dates = new Set(overall.map(row => row.leaderboard_publish_date));
  if (dates.size !== 1) throw new Error('Mixed dataset publication dates');
  const date = [...dates][0];
  const published = Date.parse(`${date}T00:00:00Z`);
  if (!/^\d{4}-\d{2}-\d{2}$/.test(date ?? '') || !Number.isFinite(published)
    || new Date(published).toISOString().slice(0, 10) !== date || published > now + 300000) throw new Error('Invalid publication date');
  const names = new Map(), ranks = new Set();
  for (const row of overall) names.set(row.model_name, (names.get(row.model_name) ?? 0) + 1);
  const safe = value => typeof value === 'string' && value.trim().length > 0 && value.length <= 256 && !/[\x00-\x1f\x7f]/.test(value);
  const entries = overall.map(row => {
    const rank = Number(row.rank), voteCount = Number(row.vote_count);
    if (!safe(row.model_name) || (row.organization != null && row.organization !== '' && !safe(row.organization))
      || !Number.isFinite(row.rating) || Math.abs(row.rating) > 100000
      || !Number.isSafeInteger(rank) || rank < 1 || ranks.has(rank)
      || row.vote_count == null || !Number.isSafeInteger(voteCount) || voteCount < 0) throw new Error('Invalid dataset row');
    ranks.add(rank);
    const openness = classifyLicense({ license: row.license });
    const organization = policy.companyNames[(row.organization ?? '').toLowerCase().replace(/[^\p{L}\p{N}]/gu, '')] ?? row.organization;
    // Some official snapshots contain two runs with the same display name.
    // Keep both original rows; use a local identity suffix only for those runs.
    const modelID = names.get(row.model_name) > 1 ? `${row.model_name}#arena-rank-${rank}` : row.model_name;
    return { rank, name: row.model_name, modelID, ...(organization && { organization }), score: row.rating,
      voteCount, ...(typeof row.license === 'string' && { modelLicense: row.license }),
      ...(openness && { openness }) };
  }).sort((a, b) => a.rank - b.rank);
  if (entries.length < (kind === 'arenaVideoEditing' ? 10 : 20) || entries.length > 5000 || entries.some((row, i) => row.rank !== i + 1)
    || entries.some((row, i) => i && row.score > entries[i - 1].score)) throw new Error('Incomplete dataset ranking');
  return { kind, title: 'Arena | ' + arenaSubsets[kind], sourceUpdatedAt: new Date(published).toISOString(),
    fetchedAt: new Date(now).toISOString(), sourceDatasetRevision: revision,
    sourceNote: `${notice.credit} · ${arenaSubsets[kind]}/latest/${category}\n${notice.sourceURL}\n${notice.sourceURL}/tree/${revision}\n${notice.licenseURL}\n${notice.changes.en}`,
    entries };
}

export async function readBounded(response, limit) {
  if (!response.ok || Number(response.headers.get('content-length')) > limit) throw new Error('Dataset unavailable');
  const chunks = []; let size = 0;
  for await (const chunk of response.body) {
    size += chunk.length; if (size > limit) throw new Error('Dataset too large');
    chunks.push(chunk);
  }
  return Buffer.concat(chunks);
}

export async function loadArenaDataset(kind, { fetcher = fetch, now = Date.now(), signal = AbortSignal.timeout(7000), includeRelated = false } = {}) {
  if (!isArena(kind)) throw new Error('Unknown Arena subset');
  const info = JSON.parse((await readBounded(await fetcher('https://huggingface.co/api/datasets/lmarena-ai/leaderboard-dataset',
    { signal, redirect: 'error', headers: { Accept: 'application/json' } }), 250000)).toString('utf8'));
  if (!/^[a-f0-9]{40}$/.test(info.sha ?? '') || info.cardData?.license !== 'cc-by-4.0') throw new Error('Unverified dataset revision or license');
  // Pin the file to the revision whose license was checked, not a mutable main URL.
  const bytes = await readBounded(await fetcher(arenaDataURL(kind, info.sha), { signal }), 4 * 1024 * 1024);
  const { parquetMetadata, parquetReadObjects } = await import('hyparquet');
  const file = bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength);
  const metadata = parquetMetadata(file);
  if (Number(metadata.num_rows) > 50000) throw new Error('Dataset too many rows');
  const rows = await parquetReadObjects({ file, metadata });
  const { modelOpenness } = await import('./parser.mjs');
  signal.throwIfAborted();
  return parseArenaAcquisitionRows(kind, rows, { now, revision: info.sha, classifyLicense: modelOpenness, includeRelated });
}

export function parseArenaAcquisitionRows(kind, rows, { includeRelated = true, ...options } = {}) {
  const parse = candidate => parseArenaRows(candidate, rows, options);
  const board = parse(kind);
  if (!includeRelated) return board;
  const relatedBoards = [];
  for (const candidate of arenaAcquisitionKinds(kind).filter(candidate => candidate !== kind)) {
    try { relatedBoards.push(parse(candidate)); } catch { /* Keep that category's last complete snapshot. */ }
  }
  return { ...board, relatedBoards };
}
