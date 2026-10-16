import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import { createBrandRules } from '../fc/domain.mjs';
import { countryCode } from '../fc/countries.mjs';

const catalog = JSON.parse(readFileSync(new URL('../fc/brand-catalog.json', import.meta.url)));
const rules = createBrandRules(catalog);

// Audit saved responses from all board kinds without requesting a source refresh.
// A valid region attached to the wrong developer is still a coverage failure.
export function auditCountryCoverage(boards) {
  const missing = [], summary = [];
  let total = 0;
  for (const board of boards) {
    if (!board || !Array.isArray(board.entries)) throw Error('Expected a leaderboard snapshot');
    let ready = 0;
    for (const entry of board.entries) {
      total++;
      const key = rules.brandKey(entry), metadata = entry.developerCountry;
      const valid = key && rules.normalizedBrandKey(metadata?.key) === key && countryCode(metadata?.countryCode);
      if (valid) ready++;
      else missing.push({ kind: board.kind, name: entry.name, organization: entry.organization ?? null,
        key, reason: !key ? 'missing-developer' : !countryCode(metadata?.countryCode) ? 'missing-country' : 'developer-mismatch',
        status: metadata?.status ?? 'missing' });
    }
    summary.push({ kind: board.kind, total: board.entries.length, ready, missing: board.entries.length - ready });
  }
  return { total, ready: total - missing.length, missingCount: missing.length, boards: summary, missing };
}

if (process.argv[1] && pathToFileURL(resolve(process.argv[1])).href === import.meta.url) {
  const paths = process.argv.slice(2).filter(value => value !== '--require-complete');
  if (!paths.length) throw Error('Usage: node Scripts/audit-country-coverage.mjs [--require-complete] <board.json> ...');
  const boards = paths.map(path => { const value = JSON.parse(readFileSync(path)); return value.board ?? value; });
  const report = auditCountryCoverage(boards);
  console.log(JSON.stringify(report, null, 2));
  if (process.argv.includes('--require-complete') && report.missingCount) process.exitCode = 1;
}
