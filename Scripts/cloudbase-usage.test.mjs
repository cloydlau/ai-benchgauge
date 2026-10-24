import assert from 'node:assert/strict';
import test from 'node:test';
import { createServer } from 'node:http';
import { once } from 'node:events';
import { parseCloudBaseUsage, loadCloudBaseUsage, cloudbaseSource, cloudbaseInterval } from '../fc/cloudbase-usage.mjs';
import { SharedLeaderboards } from '../fc/service.mjs';
import { handler } from '../fc/server.mjs';
import { modelMatcher } from '../fc/models-dev.mjs';
import { companyRows } from '../fc/domain.mjs';
import { normalizeBoard, visibleRows } from '../apps/weapp/src/core/leaderboard.js';
import { cloudbaseNotice } from '../apps/weapp/src/core/cc-by-4.0.js';

const now = Date.parse('2026-10-23T08:00:00Z');
const rows = (names = [['Kimi-K3', 30], ['GLM-5.3', 20], ['Other', 50]]) => names.map(([name, score]) => `<li class="mtv__legendItem"><span class="mtv__legendName">${name}</span><span class="mtv__legendPct">${score}<!-- -->%</span></li>`).join('');
const html = (items = rows()) => `输入 Token 与输出 Token 之和，含缓存命中；北京时间<figure aria-label="云开发 AI 模型 Token 用量分布图"><span class="mtv__range">7 个统计日</span><ol class="mtv__legend">${items}</ol></figure><figure aria-label="云开发 AI 模型请求次数分布图"><ol class="mtv__legend">${rows([['Wrong metric', 100]])}</ol></figure>`;

test('CloudBase uses published cumulative family shares, not requests, daily averages or inferred dates', () => {
  const board = parseCloudBaseUsage(html(), { now });
  assert.equal(board.entries.length, 2); assert.equal(board.sourceUpdatedAt, undefined);
  assert.equal(board.entries[0].name, 'Kimi K3'); assert.equal(board.entries[0].organization, 'moonshotai');
  assert.deepEqual(board.entries.map(e => e.score), [30, 20]); assert.equal(board.otherSharePercent, 50);
  const tied = parseCloudBaseUsage(html(rows([['GLM-5.2', 40], ['DeepSeek-V4-Pro', 40], ['Other', 20]])), { now });
  assert.deepEqual(tied.entries.map(e => e.name), ['GLM 5.2', 'DeepSeek V4 Pro'], 'Rounded ties preserve the official order');
  assert.equal(board.entries[0].totalTokens, undefined); assert.match(board.sourceNote, /7 sampled/);
  const view = visibleRows(normalizeBoard(board, 'cloudbaseUsage'));
  assert.equal(view[0].scoreText, '30.00%'); assert.equal(view[0].scoreShare, '');
  const sum = companyRows([...board.entries, { ...board.entries[0], rank: 3, name: 'Other exact Kimi family', score: 10 }], { summingUsage: true });
  assert.equal(sum[0].score, 40); assert.equal(sum[0].totalTokens, undefined);
  const company = visibleRows(normalizeBoard(board, 'cloudbaseUsage'), { grouping: 'company' });
  assert.equal(company[0].components[0].score, '30.00%');
});
test('CloudBase rejects broken scope, incomplete totals, duplicates, nonnumeric shares and changed methodology', () => {
  for (const invalid of [html().replace('Token 用量分布图', 'Token X'), html().replace('7 个统计日', 'unknown'),
    html().replace('含缓存命中', 'unknown'), html(rows([['Kimi-K3', 99]])), html(rows([['Other', 100]])),
    html(rows([['Kimi-K3', 30], ['Kimi-K3', 20], ['Other', 50]])),
    html(rows([['Kimi-K3', 'NaN'], ['Other', 50]])), html(rows([['Kimi-K3', -1], ['Other', 101]])),
    html(rows([['Kimi-K3', '30<script>1</script>'], ['Other', 50]])), html(rows([['<bad>', 50], ['Other', 50]]))]) assert.throws(() => parseCloudBaseUsage(invalid, { now }));
});
test('CloudBase identities require exact source family and canonical developer/model; no K3 or version substring', () => {
  const board = parseCloudBaseUsage(html(rows([['Kimi-K3', 30], ['K3', 10], ['Kimi-K3-Other', 10], ['Other', 50]])), { now });
  assert.equal(board.entries[1].organization, undefined); assert.equal(board.entries[2].cloudbaseCanonicalID, undefined);
  const model = { id: 'moonshotai/kimi-k3', name: 'Kimi K3', offers: [] };
  const match = modelMatcher({ models: [model, { id: 'other/kimi-k3', name: 'Kimi K3', offers: [] }, { id: 'moonshotai/kimi-k3-1017', name: 'Kimi K3 1017', offers: [] }] });
  assert.equal(match(board.entries[0], 'cloudbaseUsage'), model);
  const glm = { id: 'zhipuai/glm-5.3', name: 'GLM 5.3', offers: [] };
  assert.equal(modelMatcher({ models: [glm] })({ cloudbaseCanonicalID: 'zai/glm-5.3' }, 'cloudbaseUsage'), glm);
  assert.equal(modelMatcher({ models: [glm] })({ cloudbaseCanonicalID: 'zai/glm-5.3-flash' }, 'cloudbaseUsage'), null);
  assert.equal(match(board.entries[1], 'cloudbaseUsage'), null);
  assert.equal(match({ ...board.entries[0], cloudbaseCanonicalID: undefined }, 'cloudbaseUsage'), null);
});
test('CloudBase acquisition is keyless, bounded and fixed to official public document without executing JS', async () => {
  let calls = 0;
  const b = await loadCloudBaseUsage({ now, fetcher: async (url, options) => {
    calls++; assert.equal(url, cloudbaseSource); assert.equal(options.redirect, 'error'); assert.equal(options.headers.Authorization, undefined);
    return new Response(html());
  } });
  assert.equal(calls, 1); assert.equal(b.kind, 'cloudbaseUsage');
  for (const response of [new Response('', { status: 503 }), new Response('invalid'), new Response('x'.repeat(2 * 1024 * 1024 + 1))]) await assert.rejects(loadCloudBaseUsage({ now, fetcher: async () => response }));
});
class Store {
  boards = new Map(); states = new Map();
  async readBoard(kind) { return this.boards.get(kind) ?? null; }
  async writeBoard(kind, board) { this.boards.set(kind, board); }
  async readState(key) { return this.states.get(key) ?? { position: 0, state: null }; }
  async appendState(key, position, state) {
    if ((this.states.get(key)?.position ?? 0) !== position) return false;
    this.states.set(key, { position: position + 1, state }); return true;
  }
}
test('restored CloudBase shares daily acquisition across clients, isolates sources, retains cache and retries after failures', async () => {
  let time = now, calls = 0, fail = false;
  const store = new Store(), service = new SharedLeaderboards(store, { clock: () => time,
    cloudbaseUsage: async ({ now }) => { calls++; if (fail) throw Error('upstream unavailable'); return parseCloudBaseUsage(html(), { now }); } });
  const results = await Promise.all([service.refresh('cloudbaseUsage'), service.refresh('cloudbaseUsage')]);
  assert.equal(calls, 1); assert.ok(results.some(result => result.board));
  assert.ok(results.every(result => !result.grant && !result.configurationRequired));
  await service.refresh('cloudbaseUsage'); assert.equal(calls, 1);
  assert.equal((await service.read('openRouterUsage')).configurationRequired, true);
  time += cloudbaseInterval; fail = true;
  const retained = (await service.refresh('cloudbaseUsage')).board;
  assert.equal(retained.entries[0].name, 'Kimi K3');
  assert.equal((await service.refresh('cloudbaseUsage')).board.fetchedAt, retained.fetchedAt);
  assert.equal(calls, 2);
  store.boards.clear(); time += 600001;
  await assert.rejects(service.refresh('cloudbaseUsage'), { status: 503, message: 'Tencent usage temporarily unavailable' });
  time += 600001; fail = false;
  assert.ok((await service.refresh('cloudbaseUsage')).board);
  await assert.rejects(service.contribute('cloudbaseUsage', 'x'.repeat(43), html()), { status: 403 });
});
test('restored CloudBase GET and refresh serve the shared snapshot without client contribution grants', async t => {
  let calls = 0;
  const service = new SharedLeaderboards(new Store(), { clock: () => now,
    cloudbaseUsage: async () => { calls++; return parseCloudBaseUsage(html(), { now }); } });
  const server = createServer(handler(() => service)); server.listen(0, '127.0.0.1'); await once(server, 'listening');
  t.after(() => { server.closeAllConnections(); server.close(); });
  const base = `http://127.0.0.1:${server.address().port}/v1/boards/cloudbaseUsage`;
  for (const [path, method] of [['', 'GET'], ['/refresh', 'POST']]) {
    const response = await fetch(base + path, { method });
    assert.equal(response.status, 200);
    const payload = await response.json();
    assert.equal(payload.board.kind, 'cloudbaseUsage'); assert.equal(payload.board.entries[0].score, 30);
    assert.equal(payload.grant, undefined); assert.equal(payload.configurationRequired, undefined);
  }
  assert.equal(calls, 1);
  const response = await fetch(base + '/contribute', { method: 'POST', headers: { 'content-type': 'text/html' }, body: html() });
  assert.equal(response.status, 403);
});
test('CloudBase source notice works offline and never grants the CC BY license used by other sources', () => {
  for (const language of ['en', 'zh-CN', 'zh-TW']) {
    const note = cloudbaseNotice('Cached CloudBase provenance', language);
    assert.match(note, /Cached CloudBase provenance/); assert.ok(note.length > 100);
    assert.match(cloudbaseNotice(null, language), /https:\/\/docs.cloudbase.net/);
    assert.ok(!note.includes('creativecommons.org/licenses'));
  }
});
