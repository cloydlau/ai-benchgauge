const statuses = new Set(['open', 'closed']);
const settings = new Set(['reasoning', 'effort', 'max', 'xhigh', 'high', 'medium', 'low', 'standard', 'default', 'fallback', 'with', 'adaptive']);
const words = value => String(value ?? '').toLowerCase().match(/[\p{L}\p{N}]+/gu) ?? [];

function modelName(value) {
  // Keep parameter counts, dates and other model variants. Only inference
  // settings can be omitted when comparing a model with its agent run.
  return words(String(value ?? '').replace(/\(([^()]*)\)/g, (group, contents) => {
    const tokens = words(contents);
    return tokens.length && tokens.every(token => settings.has(token)) ? '' : group;
  })).join('-');
}

export const codingKinds = new Set(['artificialAnalysisCodingAgent', 'codeArenaWebDev', 'valsSWEbench']);

// Read-time metadata only: never change the stored ranking, its timestamps or
// the source's explicit classification. Conflicting evidence stays unknown.
export function withCodingOpenness(board, references) {
  if (!codingKinds.has(board?.kind)) return board;
  const names = new Map(), ids = new Map();
  const add = (index, key, status) => {
    if (!key) return;
    const values = index.get(key) ?? new Set();
    values.add(status); index.set(key, values);
  };
  for (const reference of references) for (const entry of reference?.entries ?? []) {
    if (!statuses.has(entry.openness)) continue;
    add(names, modelName(entry.name), entry.openness);
    add(ids, entry.modelID, entry.openness);
  }
  return { ...board, entries: board.entries.map(entry => {
    if (statuses.has(entry.openness)) return entry;
    let name = board.kind === 'artificialAnalysisCodingAgent' ? entry.name.split(' - ').at(-1) : entry.name;
    // Claude Code omits the Claude brand on some exact lead-model labels.
    if (board.kind === 'artificialAnalysisCodingAgent' && entry.name.startsWith('Claude Code - ')
        && /^(?:Sonnet|Opus|Haiku|Fable)\s+\d/.test(name)) name = `Claude ${name}`;
    const evidence = new Set([...(ids.get(entry.modelID) ?? []), ...(names.get(modelName(name)) ?? [])]);
    return evidence.size === 1 ? { ...entry, openness: [...evidence][0] } : entry;
  }) };
}
