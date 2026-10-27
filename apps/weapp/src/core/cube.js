export const cubeIndex = (face, count) => ((face % count) + count) % count

export function cubeTarget(face, destination, count) {
  const target = cubeIndex(destination, count), distance = target - face
  return Math.abs(distance) * 2 > count ? target + (distance > 0 ? -count : count) : target
}

// Sources are linear within a tab; only the category tabs wrap.
export function cubeNavigation(category, destination, counts) {
  if (destination < 0) {
    category = cubeIndex(category - 1, counts.length)
    return { category, face: counts[category] - 1 }
  }
  if (destination >= counts[category]) return { category: cubeIndex(category + 1, counts.length), face: 0 }
  return { category, face: destination }
}

export function cubeRenderedFace(index, origin, direction, count) {
  if (index === origin) return origin
  return index === cubeIndex(origin + direction, count) ? origin + direction : origin + direction * 2
}

// The cube can take a short route across the last/first source. Interpolate
// between the actual tab slots rather than exposing its unwrapped position.
export function cubeTabPosition(position, origin, direction, count) {
  const progress = Math.max(0, Math.min(1, (position - origin) * direction))
  return origin + (cubeIndex(origin + direction, count) - origin) * progress
}

// Match the native App's edge-hinged, 90-degree faces. At rest the active
// scroll-view has no transform, so its native hit testing stays ordinary.
export function cubeFaceStyle(index, position, duration = 0, active = false, origin = 0, direction = 1) {
  const distance = index - position
  const flat = Math.abs(distance) < 0.0001
  // CSS receives the destination before it interpolates. Keep the same two
  // hosts and hinges at both endpoints, including when the incoming face is flat.
  const visibleDuringTurn = active && (index === origin || index === origin + direction)
  const hidden = Math.abs(distance) > 0.9999 || (active && !visibleDuringTurn)
  const hinge = active ? (index === origin ? -direction : direction) : distance
  return `transform:${flat ? 'none' : `translateX(${distance * 100}%) rotateY(${hidden && !visibleDuringTurn ? 0 : distance * 90}deg)`};transform-origin:${hinge > 0 ? 'left' : 'right'} center;transition-duration:${duration}ms;opacity:${hidden && !visibleDuringTurn ? 0 : 1};z-index:${Math.abs(distance) <= 0.5 ? 2 : 1};pointer-events:${flat ? 'auto' : 'none'};`
}

export function cubeGesture(face, x, y, time, count = 2) {
  return { face, count, x, y, lastX: x, lastTime: time, velocity: 0, axis: '', position: face }
}

// Reserve the leftmost 32 logical pixels for WeChat's swipe-back/exit gesture.
// Decide before tracking a turn: touchcancel can arrive after visible motion.
export const isBackSwipe = (startX, dx) => startX <= 32 && dx > 0

export function moveCubeGesture(gesture, x, y, time, width) {
  const dx = x - gesture.x, dy = y - gesture.y
  if (!gesture.axis) {
    // Allow a slanted horizontal start; wait while a short diagonal is unclear.
    // Once chosen, the axis stays locked until the finger lifts.
    if (isBackSwipe(gesture.x, dx)) gesture.axis = 'navigation'
    else if (Math.abs(dx) >= 16 && Math.abs(dx) > Math.abs(dy) * 1.25) gesture.axis = 'horizontal'
    else if (Math.abs(dy) >= 8 && Math.abs(dy) >= Math.abs(dx)) gesture.axis = 'vertical'
  }
  const elapsed = time - gesture.lastTime
  if (elapsed > 0) gesture.velocity = (x - gesture.lastX) / elapsed
  gesture.lastX = x; gesture.lastTime = time
  if (gesture.axis === 'horizontal') gesture.position = Math.max(gesture.face - 1, Math.min(gesture.face + 1, gesture.face - dx / Math.max(1, width)))
  return gesture
}

export function cubeDestination(gesture, width, time) {
  if (gesture.axis !== 'horizontal') return gesture.face
  // Commit after 25% of the screen in either direction, retaining natural
  // finger tracking. A flick can advance sooner; a pause drops old velocity.
  const velocity = time - gesture.lastTime < 100 ? gesture.velocity : 0
  const projected = Math.max(gesture.face - 1, Math.min(gesture.face + 1, gesture.position - velocity * 160 / Math.max(1, width)))
  const travel = projected - gesture.face
  return Math.abs(travel) >= 0.25 ? gesture.face + Math.sign(travel) : gesture.face
}

export function matchingScroll({ scrollTop, origin, nextOrigin, rowHeight, count }) {
  if (scrollTop < origin || !count) return Math.min(scrollTop, nextOrigin)
  const index = Math.min(count - 1, Math.max(0, Math.ceil((scrollTop - origin) / rowHeight)))
  return nextOrigin + index * rowHeight
}
