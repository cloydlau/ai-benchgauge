import test from 'node:test';
import assert from 'node:assert/strict';
import { fitDomainScore, parseEpochCyber, parseEpochDomain } from '../fc/epoch-domain-fit.mjs';

test('recovers an independently constructed capability from different benchmarks', () => {
  const expected = 162.375;
  const rows = [{ difficulty: 130, slope: 0.04 }, { difficulty: 165, slope: 0.13 }, { difficulty: 195, slope: 0.08 }]
    .map(item => ({ ...item, performance: 1 / (1 + Math.exp(-item.slope * (expected - item.difficulty))) }));
  assert.ok(Math.abs(fitDomainScore(rows) - expected) < 1e-4);
  assert.equal(fitDomainScore(rows.slice(0, 1)), null);
});

test('handles edge scores and rejects bad inputs', () => {
  assert.ok(Number.isFinite(fitDomainScore([{ performance: 0, difficulty: 120, slope: 0.1 }, { performance: 1, difficulty: 150, slope: 0.1 }])));
  assert.throws(() => fitDomainScore([{ performance: 0.2, difficulty: 120, slope: 0 }, { performance: 0.4, difficulty: 130, slope: 0.1 }]));
  assert.throws(() => fitDomainScore([{ performance: 2, difficulty: 120, slope: 0.1 }, { performance: 0.4, difficulty: 130, slope: 0.1 }]));
});

// Epoch Cyber ECI data, retrieved 2026-10-31, CC BY 4.0: https://epoch.ai/eci
test('matches a published Cyber ECI score using its own benchmark parameters', () => {
  const observations = [
    [0.232, 179.08957521021065, 0.1513338952140308],
    [0.315, 173.60739667891312, 0.3021084221483168],
    [0.444, 171.9000033297432, 0.2434043954766294],
    [0.53, 170.49080044476997, 0.1388595813250342],
    [0.59, 169.0279694894893, 0.2225933395817758],
    [0.854, 160.7916931232761, 0.1846509935724131],
    [0.902, 161.7942780045008, 0.1949449623663795],
  ].map(([performance, difficulty, slope]) => ({ performance, difficulty, slope }));
  assert.ok(Math.abs(fitDomainScore(observations) - 171.0312025097173) < 1e-5);
});


test('Cyber requires its own two benchmark results and rejects mismatched files', () => {
  const parameters = 'benchmark_name,edi,estimated_slope_scaled\na,130,0.1\nb,150,0.1';
  const expected = 140;
  const a = 1 / (1 + Math.exp(-0.1 * (expected - 130)));
  const b = 1 / (1 + Math.exp(-0.1 * (expected - 150)));
  const scores = 'Model,Display name,eci,Organization,Model accessibility\n' + Array.from({ length: 21 }, (_, i) => `m${i},Model ${i},140,Maker,API access`).join('\n');
  const header = 'model_group,benchmark,performance\n';
  const results = header + Array.from({ length: 21 }, (_, i) => `m${i},a,${a}\n` + (i < 20 ? `m${i},b,${b}\n` : '')).join('');
  const board = parseEpochCyber(scores, results, parameters, 0);
  assert.equal(board.entries.length, 20);
  assert.equal(board.entries[0].score, 140);
  assert.equal(board.entries[0].openness, 'closed');
  assert.ok(!board.entries.some(row => row.modelID === 'm20'));
  assert.throws(() => parseEpochCyber(scores.replace('m0,Model 0,140', 'm0,Model 0,180'), results, parameters, 0), /disagree/);
  assert.throws(() => parseEpochCyber(scores, results, parameters.replace('benchmark_name', 'wrong'), 0), /header/);
});


test('domain scores are refitted only from selected benchmarks for eligible official models', () => {
  const parameters = 'benchmark_name,edi,estimated_slope_scaled\na,130,0.1\nb,150,0.1\nc,180,0.1';
  const a = 1 / (1 + Math.exp(-1)), b = 1 / (1 + Math.exp(1));
  const scores = 'Model,Display name,eci,Organization,Country (of organization),Accessibility group\n' + Array.from({ length: 21 }, (_, i) => `m${i},Model ${i},175,Maker,US,Closed weights`).join('\n');
  const results = 'model,benchmark,performance\n' + Array.from({ length: 21 }, (_, i) => `m${i},a,${a}\n` + (i < 20 ? `m${i},b,${b}\n` : '') + `m${i},c,0.99\n`).join('');
  const board = parseEpochDomain('epochMathECI', scores, results, parameters, ['a', 'b'], 0);
  assert.equal(board.entries.length, 20);
  assert.ok(Math.abs(board.entries[0].score - 140) < 1e-5);
  assert.equal(board.entries[0].openness, 'closed');
  assert.throws(() => parseEpochDomain('epochMathECI', scores, results, parameters, ['a', 'missing'], 0), /preset/);
  assert.throws(() => parseEpochDomain('epochCyberECI', scores, results, parameters, ['a', 'b'], 0), /preset/);
});
