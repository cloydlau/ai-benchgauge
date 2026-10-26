import assert from 'node:assert/strict'
import test from 'node:test'
import { boardTransitions, normalizeBoardTransition, boardFaceStyle } from '../src/core/board-transition.js'
import { cubeRenderedFace } from '../src/core/cube.js'

const css = value => Object.fromEntries(value.split(';').filter(Boolean).map(pair => pair.split(':')))

test('new and obsolete preferences default to cube, with three distinct available presentations', () => {
  assert.deepEqual(boardTransitions, ['cube', 'slide', 'fade'])
  for (const invalid of [undefined, null, '', 'retired', {}, 1]) assert.equal(normalizeBoardTransition(invalid), 'cube')
  for (const style of boardTransitions) assert.equal(normalizeBoardTransition(style), style)
  const cube = css(boardFaceStyle('cube', 0, 0.5, 420, true, 0, 1))
  const slide = css(boardFaceStyle('slide', 0, 0.5, 420, true, 0, 1))
  const fade = css(boardFaceStyle('fade', 0, 0.5, 420, true, 0, 1))
  assert.match(cube.transform, /rotateY/)
  assert.equal(slide.transform, 'translateX(-50%)')
  assert.equal(slide.opacity, '1')
  assert.equal(fade.opacity, '0.5')
  assert.match(fade.transform, /scale/)
})

test('all presentations keep adjacent hosts continuous in both directions, hide unrelated faces and restore native hit testing at rest', () => {
  for (const style of boardTransitions) for (const count of [2, 3]) for (const direction of [-1, 1]) {
    const origin = direction === 1 ? 0 : count - 1
    for (const progress of [0, 0.25, 0.5, 0.75, 1]) {
      const position = origin + direction * progress
      const faces = Array.from({ length: count }, (_, index) => {
        const rendered = cubeRenderedFace(index, origin, direction, count)
        return css(boardFaceStyle(style, rendered, position, 0, true, origin, direction))
      })
      assert.ok(faces.every(face => !Object.values(face).some(value => /NaN|undefined/.test(value))))
      assert.equal(faces.filter(face => face['pointer-events'] === 'auto').length, progress === 0 || progress === 1 ? 1 : 0)
      if (style === 'fade') {
        assert.ok(Math.abs(faces.reduce((sum, face) => sum + Number(face.opacity), 0) - 1) < 1e-9)
      } else {
        assert.equal(faces.filter(face => face.opacity === '1').length, 2, 'Both endpoints remain mounted throughout a transition')
      }
      assert.ok(faces.every(face => Number(face['--face-opacity']) >= 0 && Number(face['--face-opacity']) <= 1))
    }
    const resting = Array.from({ length: count }, (_, index) => css(boardFaceStyle(style, index, origin)))
    assert.equal(resting.filter(face => face.opacity === '1').length, 1)
    assert.equal(resting[origin].transform, 'none')
    assert.equal(resting[origin]['pointer-events'], 'auto')
  }
})
