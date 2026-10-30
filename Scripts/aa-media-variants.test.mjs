import test from 'node:test';
import assert from 'node:assert/strict';
import { parseBoard, sources } from '../fc/parser.mjs';

const page = entries => `<script>self.__next_f.push([1,${JSON.stringify(JSON.stringify({ entries }))}])</script>`;
const rows = (count, field) => Array.from({ length: count }, (_, i) => ({
  formatted: { rank: i + 1 }, values: { id: `id-${i}`, name: `Model ${i}`, elo: 1200 - i, [field]: 10 }
}));

test('AA media variants retain the first ranking and the source price unit', () => {
  for (const [kind, field, count, expected] of [
    ['artificialAnalysisImageEditing', 'pricePer1kImages', 20, 0.01],
    ['artificialAnalysisImageToVideo', 'pricePerMinute', 20, 10],
    ['artificialAnalysisVideoEditing', 'pricePerMinute', 10, 10],
  ]) {
    const board = parseBoard(kind, page([...rows(count, field), ...rows(count, field).map((row, i) => ({ ...row, values: { ...row.values, id: `other-${i}`, name: `Other ${i}`, elo: 1500 } }))]), Date.now());
    assert.equal(board.entries.length, count);
    assert.equal(board.entries[0].name, 'Model 0');
    assert.equal(board.entries[0].taskCostUSD, expected);
    assert.ok(sources[kind][0].startsWith('https://artificialanalysis.ai/'));
    assert.throws(() => parseBoard(kind, page(rows(count - 1, field)), Date.now()), /Incomplete source data/);
  }
});
