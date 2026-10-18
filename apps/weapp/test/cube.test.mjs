import assert from 'node:assert/strict'
import test from 'node:test'
import { cubeFaceStyle, cubeGesture, moveCubeGesture, cubeDestination, matchingScroll } from '../src/core/cube.js'

test('cube gesture locks vertical scrolling, clamps edges and distinguishes flicks from paused drags', () => {
  const vertical = cubeGesture(0, 200, 100, 0)
  moveCubeGesture(vertical, 202, 120, 20, 375)
  moveCubeGesture(vertical, 50, 160, 60, 375)
  assert.equal(vertical.axis, 'vertical'); assert.equal(vertical.position, 0)
  const diagonal = cubeGesture(0, 200, 100, 0)
  assert.equal(moveCubeGesture(diagonal, 180, 120, 20, 375).axis, 'vertical')
  const flick = cubeGesture(0, 250, 100, 0)
  moveCubeGesture(flick, 180, 102, 50, 375)
  assert.equal(cubeDestination(flick, 375, 60), 1)
  assert.equal(cubeDestination(flick, 375, 200), 0)
  moveCubeGesture(flick, -400, 102, 250, 375)
  assert.equal(flick.position, 1)
  const back = cubeGesture(1, 100, 100, 0)
  moveCubeGesture(back, 310, 100, 500, 375)
  assert.equal(cubeDestination(back, 375, 700), 0)
})

test('a paused drag switches at 25% width in both directions without accepting smaller or outward drags', () => {
  for (const width of [320, 375, 430]) {
    for (const face of [0, 1]) {
      const direction = face === 0 ? -1 : 1
      for (const [fraction, expected] of [[0.24, face], [0.25, 1 - face], [0.26, 1 - face], [-0.4, face]]) {
        const gesture = cubeGesture(face, width / 2, 100, 0)
        moveCubeGesture(gesture, width / 2 + direction * width * fraction, 102, 500, width)
        assert.equal(cubeDestination(gesture, width, 700), expected)
      }
      const vertical = cubeGesture(face, width / 2, 100, 0)
      moveCubeGesture(vertical, width / 2 + direction * width * 0.4, 400, 500, width)
      assert.equal(cubeDestination(vertical, width, 700), face)
    }
  }
})

test('small sideways jitter and ambiguous diagonals yield to vertical scrolling for the entire touch', () => {
  for (const face of [0, 1]) {
    for (const sign of [-1, 1]) {
      const gesture = cubeGesture(face, 200, 100, 0)
      moveCubeGesture(gesture, 200 + sign * 10, 103, 20, 375)
      assert.equal(gesture.axis, '')
      moveCubeGesture(gesture, 200 + sign * 15, 120, 40, 375)
      assert.equal(gesture.axis, 'vertical')
      moveCubeGesture(gesture, 200 + sign * 220, 140, 60, 375)
      assert.equal(gesture.axis, 'vertical')
      assert.equal(gesture.position, face)
      const horizontal = cubeGesture(face, 200, 100, 0)
      moveCubeGesture(horizontal, 200 + sign * 20, 104, 20, 375)
      assert.equal(horizontal.axis, 'horizontal')
    }
  }
})

test('slanted horizontal starts wait through early jitter and stay locked through a curved path', () => {
  for (const face of [0, 1]) for (const yDirection of [-1, 1]) {
    const direction = face === 0 ? -1 : 1
    const gesture = cubeGesture(face, 200, 200, 0)
    moveCubeGesture(gesture, 200 + direction * 12, 200 + yDirection * 9, 20, 375)
    assert.equal(gesture.axis, '')
    moveCubeGesture(gesture, 200 + direction * 24, 200 + yDirection * 16, 40, 375)
    assert.equal(gesture.axis, 'horizontal')
    moveCubeGesture(gesture, 200 + direction * 150, 200 + yDirection * 180, 400, 375)
    assert.equal(gesture.axis, 'horizontal')
    assert.equal(cubeDestination(gesture, 375, 600), 1 - face)
  }
})

test('both cube faces keep their shared hinge during a turn and active native hit testing is flat at rest', () => {
  assert.match(cubeFaceStyle(0, 0.5, 0, true), /translateX\(-50%\) rotateY\(-45deg\)/)
  assert.match(cubeFaceStyle(1, 0.5, 0, true), /translateX\(50%\) rotateY\(45deg\)/)
  assert.match(cubeFaceStyle(1, 0, 0, true), /rotateY\(90deg\).*opacity:1/)
  assert.match(cubeFaceStyle(0, 1, 320, true), /rotateY\(-90deg\).*opacity:1/)
  assert.match(cubeFaceStyle(1, 1), /transform:none.*pointer-events:auto/)
  assert.match(cubeFaceStyle(0, 1), /opacity:0.*pointer-events:none/)
})

test('source switching matches the first fully visible row and clamps shorter or empty lists', () => {
  assert.equal(matchingScroll({ scrollTop: 1080, origin: 110, nextOrigin: 130, rowHeight: 48, count: 500 }), 1138)
  assert.equal(matchingScroll({ scrollTop: 1080, origin: 110, nextOrigin: 130, rowHeight: 48, count: 3 }), 226)
  assert.equal(matchingScroll({ scrollTop: 40, origin: 110, nextOrigin: 130, rowHeight: 48, count: 500 }), 40)
  assert.equal(matchingScroll({ scrollTop: 1080, origin: 110, nextOrigin: 130, rowHeight: 48, count: 0 }), 130)
})
