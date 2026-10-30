import test from 'node:test';
import assert from 'node:assert/strict';
import { parseBoard } from '../fc/parser.mjs';
import { companyRows, withRankChanges } from '../fc/domain.mjs';

const page = rows => `<script>self.__next_f.push([1,${JSON.stringify(JSON.stringify({ rows }))}])</script>`;
const data = key => Array.from({ length: 20 }, (_, i) => ({ id: `model-${i}`, displayName: `Model ${i}`, host: { name: 'Provider' }, model: { openWeights: true }, [key]: (20 - i) / 100 }));

test('speech-to-text accuracy ranks lower WER first and separates streaming measurements', () => {
  for (const [kind, key] of [['artificialAnalysisSpeechToText', 'aaWerIndex'], ['artificialAnalysisSpeechToTextStreaming', 'aaWerStreamingIndex']]) {
    const rows = data(key), board = parseBoard(kind, page([...rows, rows[0]]), Date.now());
    assert.equal(board.entries.length, 20);
    assert.equal(board.entries[0].name, 'Model 19');
    assert.equal(board.entries[0].score, 1);
    assert.equal(board.entries.at(-1).score, 20);
    assert.equal(board.entries[0].organization, 'Provider');
    assert.throws(() => parseBoard(kind, page(rows.slice(0, 19)), Date.now()), /Incomplete/);
    assert.throws(() => parseBoard(kind, page(data(key === 'aaWerIndex' ? 'aaWerStreamingIndex' : 'aaWerIndex')), Date.now()), /Incomplete/);
  }
});

test('error-rate company ranking selects the lowest WER and tracks movement', () => {
  const rows = [
    { rank: 1, name: 'Best A', modelID: 'a1', organization: 'OpenAI', score: 2 },
    { rank: 2, name: 'Best B', modelID: 'b1', organization: 'Google', score: 3 },
    { rank: 3, name: 'Weak A', modelID: 'a2', organization: 'OpenAI', score: 8 },
  ];
  const companies = companyRows(rows, { lowerIsBetter: true });
  assert.deepEqual(companies.map(row => row.name), ['OpenAI', 'Google']);
  assert.equal(companies[0].score, 2);
  const old = { kind: 'artificialAnalysisSpeechToText', entries: rows };
  const next = { kind: old.kind, entries: [{ ...rows[1], rank: 1, score: 1 }, { ...rows[0], rank: 2 }, rows[2]] };
  const updated = withRankChanges(next, old);
  assert.equal(updated.entries[0].companyRankChange.delta, 1);
  assert.equal(updated.entries[1].companyRankChange.delta, -1);
});
