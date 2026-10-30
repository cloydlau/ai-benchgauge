import test from 'node:test';
import assert from 'node:assert/strict';
import { arenaDataURL, parseArenaRows } from '../fc/arena-dataset.mjs';
import { sources } from '../fc/parser.mjs';
import { isArenaDatasetBoard, canReplace } from '../fc/domain.mjs';
import { arenaSourcePages } from '../fc/source-logos.mjs';
import { loadConfiguredArenaDataset } from '../fc/arena-collector.mjs';

const revision = 'a'.repeat(40), now = Date.parse('2026-10-30T00:00:00Z');
const rows = count => Array.from({ length: count }, (_, i) => ({
  model_name: `Model ${i}`, organization: 'Example', rating: 1500 - i,
  vote_count: 1000, rank: i + 1, category: 'overall', leaderboard_publish_date: '2026-10-20'
}));

test('Arena image-to-video and video-edit use separate official subsets', () => {
  for (const [kind, subset, count] of [['arenaImageToVideo', 'image_to_video', 20], ['arenaVideoEditing', 'video_edit', 10]]) {
    assert.ok(arenaDataURL(kind, revision).includes(`/${subset}/`));
    assert.ok(sources[kind][0].includes('arena.ai/leaderboard/'));
    const board = parseArenaRows(kind, [...rows(count), { ...rows(1)[0], category: 'other' }], { now, revision });
    assert.equal(board.entries.length, count);
    assert.equal(board.entries[0].score, 1500);
    assert.ok(isArenaDatasetBoard(board));
    assert.equal(canReplace({ ...board, sourceNote: undefined }, board), false);
    assert.equal(arenaSourcePages[kind], sources[kind][0]);
    assert.throws(() => parseArenaRows(kind, rows(count - 1), { now, revision }), /Incomplete/);
  }
});

test('collector round trip retains multi-image category', async () => {
  const kind = 'arenaMultiImageEditing';
  const board = parseArenaRows(kind, rows(20).map(row => ({ ...row, category: 'multi_image_edit' })), { now, revision });
  const environment = { ARENA_COLLECTOR_ENDPOINT: 'https://fixture.ap-southeast-1.fcapp.run', ARENA_COLLECTOR_TOKEN: 'T'.repeat(43) };
  const result = await loadConfiguredArenaDataset(kind, { now, environment, fetcher: async () => new Response(JSON.stringify(board)) });
  assert.equal(result.entries.length, 20);
  assert.ok(result.sourceNote.includes('image_edit/latest/multi_image_edit'));
  const wrong = { ...board, sourceNote: board.sourceNote.replace('latest/multi_image_edit', 'latest/overall') };
  await assert.rejects(loadConfiguredArenaDataset(kind, { now, environment, fetcher: async () => new Response(JSON.stringify(wrong)) }));
});

test('Arena single and multi-image edit retain separate dataset categories', () => {
  const single = rows(20).map(row => ({ ...row, category: 'overall', model_name: `Single ${row.rank}` }));
  const multi = rows(20).map(row => ({ ...row, category: 'multi_image_edit', model_name: `Multi ${row.rank}` }));
  for (const [kind, label, category] of [['arenaImageEditing', 'Single 1', 'overall'], ['arenaMultiImageEditing', 'Multi 1', 'multi_image_edit']]) {
    const board = parseArenaRows(kind, [...single, ...multi], { now, revision });
    assert.equal(board.entries[0].name, label);
    assert.equal(board.entries.length, 20);
    assert.ok(board.sourceNote.includes(`image_edit/latest/${category}`));
    assert.ok(isArenaDatasetBoard(board));
    assert.equal(arenaSourcePages[kind], sources[kind][0]);
  }
});
