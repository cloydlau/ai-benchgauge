import assert from 'node:assert/strict';
import test from 'node:test';
import { auditCountryCoverage } from './audit-country-coverage.mjs';
import { mkdtempSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';

test('coverage audit distinguishes absent developers, failed regions and mismatched identities across boards', () => {
  const report = auditCountryCoverage([
    { kind: 'arenaText', entries: [
      { name: 'mercury-2', organization: 'Inception AI', developerCountry: { key: 'inceptionai', countryCode: 'US', status: 'ready' } },
      { name: 'unverified model' },
      { name: 'granite', organization: 'IBM', developerCountry: { key: 'ibm', status: 'failed' } },
      { name: 'command-a', organization: 'Cohere', developerCountry: { key: 'openai', countryCode: 'US', status: 'ready' } },
    ] },
    { kind: 'arenaTextToVideo', entries: [
      { name: 'pika', organization: 'Pika Art', developerCountry: { key: 'pika', countryCode: 'US', status: 'ready' } },
      { name: 'unknown region', organization: 'New Maker', developerCountry: { key: 'newmaker', countryCode: 'ZZ' } },
    ] },
  ]);
  assert.equal(report.total, 6);
  assert.equal(report.ready, 2);
  assert.equal(report.missingCount, 4);
  assert.deepEqual(report.missing.map(row => row.reason), ['missing-developer', 'missing-country', 'developer-mismatch', 'missing-country']);
  assert.deepEqual(report.boards.map(row => row.missing), [3, 1]);
  assert.throws(() => auditCountryCoverage([null]), /snapshot/);
});

test('country audit CLI validates saved snapshots and only requires completeness when requested', t => {
  const directory = mkdtempSync(join(tmpdir(), 'country-audit-cli-'));
  t.after(() => rmSync(directory, { recursive: true, force: true }));
  const script = new URL('./audit-country-coverage.mjs', import.meta.url);
  const run = (...args) => spawnSync(process.execPath, [script.pathname, ...args], { encoding: 'utf8' });
  const complete = join(directory, 'complete.json'), missing = join(directory, 'missing.json');
  writeFileSync(complete, JSON.stringify({ board: { kind: 'arenaText', entries: [
    { name: 'Model', organization: 'New Maker', developerCountry: { key: 'newmaker', countryCode: 'TW' } },
  ] } }));
  writeFileSync(missing, JSON.stringify({ kind: 'arenaTextToVideo', entries: [{ name: 'Unknown' }] }));
  assert.match(run().stderr, /Usage:/);
  const ready = run('--require-complete', complete);
  assert.equal(ready.status, 0, ready.stderr); assert.equal(JSON.parse(ready.stdout).ready, 1);
  const partial = run(complete, missing);
  assert.equal(partial.status, 0, partial.stderr); assert.equal(JSON.parse(partial.stdout).missingCount, 1);
  assert.equal(run('--require-complete', missing).status, 1);
  writeFileSync(missing, 'not json'); assert.notEqual(run(missing).status, 0);
  const imported = spawnSync(process.execPath, ['--input-type=module', '--eval', `await import(${JSON.stringify(script.href)})`], { encoding: 'utf8' });
  assert.equal(imported.status, 0, imported.stderr); assert.equal(imported.stdout, '');
});
