import { csvRows, parseEpochECI, epochCountryCode } from './epoch-eci.mjs';
import { normalizedBrandKey } from './brands.mjs';

// Domain estimates minimize squared benchmark prediction errors on Epoch's ECI scale.
// See https://epoch.ai/data/eci-documentation/domain-specific-eci.
export function fitDomainScore(observations) {
  if (!Array.isArray(observations) || observations.length < 2) return null;
  const items = observations.map(({ performance, difficulty, slope }) => {
    if (![performance, difficulty, slope].every(Number.isFinite) || performance < 0 || performance > 1 || slope <= 0) throw new Error('Invalid ECI benchmark observation');
    return { p: Math.max(0.001, Math.min(0.999, performance)), d: difficulty, a: slope };
  });
  const loss = x => items.reduce((sum, { p, d, a }) => {
    const predicted = 1 / (1 + Math.exp(Math.max(-500, Math.min(500, -a * (x - d)))));
    return sum + (p - predicted) ** 2;
  }, 0);
  // The domain loss need not be convex: locate the best interval before refining it.
  const lo = -100, hi = 300, step = 1;
  let best = lo, bestLoss = loss(lo);
  for (let x = lo + step; x <= hi; x += step) {
    const value = loss(x);
    if (value < bestLoss) { best = x; bestLoss = value; }
  }
  let left = Math.max(lo, best - step), right = Math.min(hi, best + step);
  const ratio = (Math.sqrt(5) - 1) / 2;
  let x1 = right - ratio * (right - left), x2 = left + ratio * (right - left);
  let y1 = loss(x1), y2 = loss(x2);
  while (right - left > 1e-8) {
    if (y1 < y2) { right = x2; x2 = x1; y2 = y1; x1 = right - ratio * (right - left); y1 = loss(x1); }
    else { left = x1; x1 = x2; y1 = y2; x2 = left + ratio * (right - left); y2 = loss(x2); }
  }
  return (left + right) / 2;
}

// The source score file supplies the known model list; benchmark results establish
// eligibility and are fitted separately. Do not invent rows from a broader corpus.
export function parseEpochCyber(scoresCSV, resultsCSV, parametersCSV, now = Date.now()) {
  function records(csv, required) {
    const [header = [], ...rows] = csvRows(csv);
    if (new Set(header).size !== header.length || required.some(key => !header.includes(key))) throw new Error('Invalid Epoch Cyber CSV header');
    return rows.map(row => {
      if (row.length !== header.length) throw new Error('Incomplete Epoch Cyber CSV row');
      return Object.fromEntries(header.map((name, i) => [name, row[i].trim()]));
    });
  }
  const parameters = new Map();
  for (const row of records(parametersCSV, ['benchmark_name', 'edi', 'estimated_slope_scaled'])) {
    const name = row.benchmark_name, difficulty = Number(row.edi), slope = Number(row.estimated_slope_scaled);
    if (!name || !row.edi || !row.estimated_slope_scaled || !Number.isFinite(difficulty) || !Number.isFinite(slope) || slope <= 0 || parameters.has(name)) throw new Error('Invalid Epoch Cyber benchmark');
    parameters.set(name, { difficulty, slope });
  }
  const observations = new Map();
  for (const row of records(resultsCSV, ['model_group', 'benchmark', 'performance'])) {
    const parametersForBenchmark = parameters.get(row.benchmark);
    if (!row.model_group || !parametersForBenchmark || !row.performance) continue;
    const performance = Number(row.performance);
    if (!Number.isFinite(performance) || performance < 0 || performance > 1) throw new Error('Invalid Epoch Cyber score');
    if (!observations.has(row.model_group)) observations.set(row.model_group, new Map());
    const group = observations.get(row.model_group), previous = group.get(row.benchmark);
    if (!previous || previous.performance < performance) group.set(row.benchmark, { performance, ...parametersForBenchmark });
  }
  const seen = new Set(), entries = [];
  for (const row of records(scoresCSV, ['Model', 'Display name', 'eci', 'Organization'])) {
    const id = row.Model, officialScore = Number(row.eci);
    if (!id || seen.has(id) || !row.eci || !Number.isFinite(officialScore)) throw new Error('Invalid Epoch Cyber model');
    seen.add(id);
    const scores = [...(observations.get(id)?.values() ?? [])];
    const calculated = fitDomainScore(scores);
    if (calculated === null) continue;
    if (Math.abs(calculated - officialScore) > 0.01) throw new Error('Epoch Cyber data files disagree');
    const access = row['Model accessibility'];
    const openness = access?.startsWith('Open weights') ? 'open' : ['API access', 'Hosted access (no API)', 'Limited access', 'Unreleased'].includes(access) ? 'closed' : undefined;
    const code = epochCountryCode(row['Country (of organization)']);
    const countryHint = code && row.Organization ? { key: normalizedBrandKey(row.Organization), countryCode: code } : null;
    entries.push({ modelID: id, name: row['Display name'] || id, score: officialScore, ...(row.Organization && { organization: row.Organization }), ...(openness && { openness }), ...(countryHint && { countryHint }) });
  }
  if (entries.length < 20 || entries.length > 5000) throw new Error('Incomplete Epoch Cyber data');
  entries.sort((a, b) => b.score - a.score || a.name.localeCompare(b.name));
  return { kind: 'epochCyberECI', title: 'Cyber ECI', sourceNote: 'Epoch AI · Cyber ECI · CC BY 4.0 · https://epoch.ai/eci', fetchedAt: new Date(now).toISOString(), entries: entries.map((entry, index) => ({ rank: index + 1, ...entry })) };
}

// The preset must come from verified Epoch benchmark metadata; do not infer a
// category from the model name or from the general ECI value.
export function parseEpochDomain(kind, scoresCSV, resultsCSV, parametersCSV, benchmarkNames, now = Date.now()) {
  if (!['epochMathECI', 'epochSoftwareECI'].includes(kind) || !Array.isArray(benchmarkNames) || benchmarkNames.length < 2 || new Set(benchmarkNames).size !== benchmarkNames.length) throw new Error('Invalid Epoch domain preset');
  function rows(csv, required) {
    const [header = [], ...data] = csvRows(csv);
    if (new Set(header).size !== header.length || required.some(key => !header.includes(key))) throw new Error('Invalid Epoch domain CSV header');
    return data.map(row => {
      if (row.length !== header.length) throw new Error('Incomplete Epoch domain CSV row');
      return Object.fromEntries(header.map((name, i) => [name, row[i].trim()]));
    });
  }
  const selected = new Set(benchmarkNames), parameters = new Map();
  for (const row of rows(parametersCSV, ['benchmark_name', 'edi', 'estimated_slope_scaled'])) {
    if (!selected.has(row.benchmark_name)) continue;
    const difficulty = Number(row.edi), slope = Number(row.estimated_slope_scaled);
    if (!row.edi || !row.estimated_slope_scaled || !Number.isFinite(difficulty) || !Number.isFinite(slope) || slope <= 0 || parameters.has(row.benchmark_name)) throw new Error('Invalid Epoch domain benchmark');
    parameters.set(row.benchmark_name, { difficulty, slope });
  }
  if (parameters.size !== selected.size) throw new Error('Epoch domain preset does not match benchmark parameters');
  const observations = new Map();
  for (const row of rows(resultsCSV, ['model', 'benchmark', 'performance'])) {
    const parameter = parameters.get(row.benchmark);
    if (!parameter || !row.model || !row.performance) continue;
    const performance = Number(row.performance);
    if (!Number.isFinite(performance) || performance < 0 || performance > 1) throw new Error('Invalid Epoch domain score');
    if (!observations.has(row.model)) observations.set(row.model, new Map());
    const group = observations.get(row.model), previous = group.get(row.benchmark);
    if (!previous || previous.performance < performance) group.set(row.benchmark, { performance, ...parameter });
  }
  const models = parseEpochECI(scoresCSV, now).entries;
  const entries = models.flatMap(model => {
    const score = fitDomainScore([...(observations.get(model.modelID)?.values() ?? [])]);
    return score === null ? [] : [{ ...model, score }];
  });
  if (entries.length < 20 || entries.length > 5000) throw new Error('Incomplete Epoch domain data');
  entries.sort((a, b) => b.score - a.score || a.name.localeCompare(b.name));
  return { kind, title: kind === 'epochMathECI' ? 'Math ECI' : 'Software engineering ECI', sourceNote: 'Epoch AI · ECI · CC BY 4.0 · https://epoch.ai/eci', fetchedAt: new Date(now).toISOString(), entries: entries.map((entry, index) => ({ ...entry, rank: index + 1 })) };
}
