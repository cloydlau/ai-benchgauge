import test from 'node:test';
import assert from 'node:assert/strict';
import { withOpenRouterModels, withOpenRouterSpeeds } from '../fc/openrouter-usage.mjs';
const board = { entries: [{ rank: 1, modelID: 'maker/model-2026', score: 4 }, { rank: 2, modelID: 'maker/model-2026:free', score: 2 }] };
const catalog = { data: [{ id: 'maker/model', canonical_slug: 'maker/model-2026', name: 'Model', architecture: { input_modalities: ['text'], output_modalities: ['text'] }, pricing: { prompt: '0.000002', completion: '0.000004' } }, { id: 'maker/model:free', canonical_slug: 'maker/model-2026', name: 'Free', architecture: { input_modalities: ['text'], output_modalities: ['text'] }, pricing: { prompt: '0', completion: '0' } }] };
test('usage joins exact official prices and preserves rank and free variants', () => {
 const result = withOpenRouterModels(board, catalog);
 assert.deepEqual(result.entries.map(e => [e.rank, e.taskCostUSD, e.outputPriceUSD]), [[1, 2, 4], [2, 0, 0]]);
 assert.deepEqual(result.entries.map(e => e.score), [4, 2]);
});
test('throughput uses the highest published provider p50; unavailable is not guessed', () => {
 const result = withOpenRouterSpeeds(withOpenRouterModels(board, catalog), new Map([
  ['maker/model', { data: { id: 'maker/model', endpoints: [{ throughput_last_30m: { p50: 25 } }, { throughput_last_30m: { p50: 40 } }, { throughput_last_30m: null }] } }],
  ['maker/model:free', { data: { id: 'maker/model:free', endpoints: [{ throughput_last_30m: null }] } }],
 ]));
 assert.equal(result.entries[0].speed, 40); assert.equal(result.entries[1].speed, undefined);
});

test('acquisition requests official provider metrics and retains pricing when a provider fails', async () => {
  const { loadOpenRouterUsage } = await import('../fc/openrouter-usage.mjs');
  const now = Date.parse('2026-10-23T10:00:00Z');
  const urls = [], endpointHeaders = [];
  const dataset = { meta: { version: 'v1', start_date: '2026-10-22', end_date: '2026-10-22', as_of: '2026-10-23T00:00:30Z' }, data: [
    { date: '2026-10-22', model_permaslug: 'maker/model-2026', total_tokens: '100' },
    { date: '2026-10-22', model_permaslug: 'maker/model-2026:free', total_tokens: '50' },
  ] };
  const fetcher = async (url, options) => {
    urls.push(url); assert.equal(options.redirect, 'error');
    if (url.includes('/datasets/')) {
      assert.equal(options.headers.Authorization, 'Bearer test-key');
      return new Response(JSON.stringify(dataset));
    }
    if (url.endsWith('/models')) {
      assert.equal(options.headers.Authorization, undefined);
      return new Response(JSON.stringify(catalog));
    }
    endpointHeaders.push(options.headers.Authorization);
    if (url.endsWith('/maker/model/endpoints')) return new Response(JSON.stringify({ data: { id: 'maker/model', endpoints: [{ throughput_last_30m: { p50: 80 } }] } }));
    return new Response('', { status: 503 });
  };
  const result = await loadOpenRouterUsage({ now, apiKey: '  test-key  ', fetcher });
  assert.equal(result.entries[0].speed, 80);
  assert.equal(result.entries[1].speed, undefined);
  assert.equal(result.entries[1].taskCostUSD, 0);
  assert.equal(urls.length, 4);
  assert.deepEqual(endpointHeaders, ['Bearer test-key', 'Bearer test-key']);
  assert.ok(!JSON.stringify(result).includes('test-key'));
  assert.ok(urls.every(url => url.startsWith('https://openrouter.ai/api/v1/')));
});
