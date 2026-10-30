import test from 'node:test';
import assert from 'node:assert/strict';
import { parseBoard, sources } from '../fc/parser.mjs';

const page = entries => `<script>self.__next_f.push([1,${JSON.stringify(JSON.stringify({ entries }))}])</script>`;
const rows = (count, prefix) => Array.from({ length: count }, (_, i) => ({
  formatted: { rank: i + 1 }, values: { id: `${prefix}-${i}`, name: `${prefix} ${i}`, elo: 1200 - i }
}));

test('speech voice boards preserve their own source and exclude later rankings', () => {
  for (const [kind, path] of [
    ['artificialAnalysisSpeechProviderVoice', 'provider-voice'],
    ['artificialAnalysisSpeechControlledVoice', 'controlled-voice'],
  ]) {
    const board = parseBoard(kind, page([...rows(20, 'Primary'), ...rows(20, 'Other')]), Date.now());
    assert.equal(new URL(sources[kind][0]).pathname, `/text-to-speech/leaderboard/${path}`);
    assert.equal(board.entries.length, 20);
    assert.equal(board.entries[0].name, 'Primary 0');
    assert.equal(board.entries[0].taskCostUSD, undefined);
    assert.throws(() => parseBoard(kind, page(rows(19, 'Primary')), Date.now()), /Incomplete source data/);
  }
});
