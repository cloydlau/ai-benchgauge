import assert from 'node:assert/strict'
import test from 'node:test'
import { cubeIndex, cubeNavigation, cubeTarget, cubeRenderedFace, cubeTabPosition, cubeFaceStyle, cubeGesture, moveCubeGesture, cubeDestination, matchingScroll } from '../src/core/cube.js'

test('source indicator maps fractional cube travel to tab slots in both directions and across short routes', () => {
  for (const count of [2, 3]) for (let origin = 0; origin < count; origin++) {
    for (const direction of [-1, 1]) for (const progress of [0, 0.1, 0.25, 0.5, 0.75, 1]) {
      const next = cubeIndex(origin + direction, count)
      assert.ok(Math.abs(cubeTabPosition(origin + direction * progress, origin, direction, count) - (origin + (next - origin) * progress)) < 1e-9)
    }
  }
  assert.equal(cubeTabPosition(-0.4, 0, 1, 3), 0)
  assert.equal(cubeTabPosition(2.4, 0, 1, 3), 1)
  assert.equal(cubeTabPosition(0.4, 0, 1, 1), 0)
})

test('left-edge right swipes yield to navigation for the entire gesture without moving or projecting a turn', () => {
  for (const count of [2, 3]) for (let face = 0; face < count; face++) {
    for (const x of [0, 16, 32]) {
      const gesture = cubeGesture(face, x, 200, 0, count)
      for (const [nextX, nextY, time] of [[x + 1, 201, 10], [280, 220, 30], [-100, 240, 50]]) {
        moveCubeGesture(gesture, nextX, nextY, time, 375)
        assert.equal(gesture.axis, 'navigation')
        assert.equal(gesture.position, face)
        assert.equal(cubeDestination(gesture, 375, time), face)
      }
    }
  }
  const ordinary = cubeGesture(1, 33, 200, 0)
  moveCubeGesture(ordinary, 280, 200, 200, 375)
  assert.equal(ordinary.axis, 'horizontal')
  assert.equal(cubeDestination(ordinary, 375, 400), 0)
  const leftward = cubeGesture(0, 32, 200, 0)
  moveCubeGesture(leftward, -100, 200, 200, 375)
  assert.equal(leftward.axis, 'horizontal')
  assert.equal(cubeDestination(leftward, 375, 400), 1)
})

test('cube gesture locks vertical scrolling, limits each turn to one neighbour and distinguishes flicks from paused drags', () => {
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

test('a paused drag switches at 25% width in both directions without accepting smaller drags', () => {
  for (const width of [320, 375, 430]) {
    for (const face of [0, 1]) {
      const direction = face === 0 ? -1 : 1
      for (const [fraction, expected] of [[0.24, face], [0.25, 1 - face], [0.26, 1 - face], [-0.4, 1 - face]]) {
        const gesture = cubeGesture(face, width / 2, 100, 0)
        moveCubeGesture(gesture, width / 2 + direction * width * fraction, 102, 500, width)
        assert.equal(cubeIndex(cubeDestination(gesture, width, 700), 2), expected)
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

test('three-source cube turns from Arena to Epoch and back with correct hinge and cyclic outer neighbours', () => {
  const next = cubeGesture(1, 250, 100, 0, 3);
  moveCubeGesture(next, 100, 100, 200, 375);
  assert.equal(next.position, 1.4);
  assert.equal(cubeDestination(next, 375, 500), 2);
  const back = cubeGesture(2, 100, 100, 0, 3);
  moveCubeGesture(back, 260, 100, 200, 375);
  assert.equal(cubeDestination(back, 375, 500), 1);
  moveCubeGesture(back, -200, 100, 600, 375);
  assert.equal(back.position, 2.8);
  assert.match(cubeFaceStyle(1, 1.4), /transform-origin:right center/);
  assert.match(cubeFaceStyle(2, 1.4), /transform-origin:left center/);
  assert.match(cubeFaceStyle(2, 2), /transform:none/);
});

test('cyclic two- and three-source cubes keep both hosts on adjacent hinges across every seam', () => {
  for (const count of [2, 3]) for (const direction of [-1, 1]) {
    let face = direction > 0 ? count - 1 : 0
    for (let turn = 0; turn < count * 3; turn++) {
      const drag = cubeGesture(face, 180, 100, 0, count)
      moveCubeGesture(drag, 180 - direction * 240, 102, 400, 375)
      const target = cubeDestination(drag, 375, 600)
      assert.equal(target, face + direction)
      const next = cubeIndex(target, count), position = face + direction * 0.5
      const outgoing = cubeRenderedFace(face, face, direction, count)
      const incoming = cubeRenderedFace(next, face, direction, count)
      assert.equal(outgoing - position, -direction * 0.5)
      assert.equal(incoming - position, direction * 0.5)
      for (const progress of [0, 0.25, 0.5, 0.75, 1]) {
        const point = face + direction * progress
        const leaving = cubeFaceStyle(outgoing, point, 420, true, face, direction)
        const entering = cubeFaceStyle(incoming, point, 420, true, face, direction)
        assert.match(leaving, new RegExp(`transform-origin:${direction > 0 ? 'right' : 'left'} center`))
        assert.match(entering, new RegExp(`transform-origin:${direction > 0 ? 'left' : 'right'} center`))
        assert.match(leaving, /opacity:1/)
        assert.match(entering, /opacity:1/)
        if (progress === 1) assert.match(entering, /transform:none/)
        for (let other = 0; other < count; other++) if (other !== face && other !== next) {
          assert.match(cubeFaceStyle(cubeRenderedFace(other, face, direction, count), point, 420, true, face, direction), /opacity:0/)
        }
      }
      face = next
    }
  }
  assert.equal(cubeTarget(2, 0, 3), 3)
  assert.equal(cubeTarget(0, 2, 3), -1)
  assert.equal(cubeTarget(0, 1, 2), 1)
  assert.equal(cubeTarget(1, 0, 2), 0)
})

test('source boundaries move between categories and only categories wrap, including a single-source tab', () => {
  const counts = [3, 3, 2, 1, 2]
  for (let category = 0; category < counts.length; category++) {
    for (let face = 0; face < counts[category]; face++) {
      assert.deepEqual(cubeNavigation(category, face, counts), { category, face })
      for (const direction of [-1, 1]) {
        const destination = face + direction
        const next = cubeNavigation(category, destination, counts)
        const expectedCategory = destination < 0 ? (category + counts.length - 1) % counts.length
          : destination >= counts[category] ? (category + 1) % counts.length : category
        assert.equal(next.category, expectedCategory)
        assert.equal(next.face, destination < 0 ? counts[expectedCategory] - 1 : destination >= counts[category] ? 0 : destination)
      }
    }
  }
})
