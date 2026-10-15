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
