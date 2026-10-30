import test from 'node:test';
import assert from 'node:assert/strict';
import { parseBoard } from '../fc/parser.mjs';

const page = results => `<script>self.__next_f.push([1,${JSON.stringify(JSON.stringify({ results }))}])</script>`;
const rows = sliceKey => Array.from({ length: 20 }, (_, i) => ({
  id: `${sliceKey}-${i}`, name: `${sliceKey} ${i}`, stsHostModelId: null,
  creatorName: 'Maker', sliceKey, rank: i + 1, elo: 1200 - i
}));

test('speech agent selects only overall results and validates source ranking', () => {
  const kind = 'artificialAnalysisSpeechAgent', now = Date.now();
  const overall = rows('overall');
  const board = parseBoard(kind, page([...rows('agentic'), ...overall, ...rows('non_agentic')]), now);
  assert.equal(board.entries.length, 20);
  assert.equal(board.entries[0].name, 'overall 0');
  assert.equal(board.entries[0].score, 1200);
  assert.throws(() => parseBoard(kind, page(overall.slice(0, 19)), now), /Incomplete/);
  assert.throws(() => parseBoard(kind, page([...overall, overall[0]]), now), /Invalid/);
  const gap = rows('overall'); gap[3].rank = 30;
  assert.throws(() => parseBoard(kind, page(gap), now), /Incomplete/);
});
