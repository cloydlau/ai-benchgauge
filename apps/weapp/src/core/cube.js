const clamp = value => Math.max(0, Math.min(1, value))

// Match the native App's edge-hinged, 90-degree faces. At rest the active
// scroll-view has no transform, so its native hit testing stays ordinary.
export function cubeFaceStyle(index, position, duration = 0, active = false) {
  const distance = index - clamp(position)
  const flat = Math.abs(distance) < 0.0001
  const hidden = Math.abs(distance) > 0.9999
  return `transform:${flat ? 'none' : `translateX(${distance * 100}%) rotateY(${hidden && !active ? 0 : distance * 90}deg)`};transform-origin:${index ? 'left' : 'right'} center;transition-duration:${duration}ms;opacity:${hidden && !active ? 0 : 1};z-index:${Math.abs(distance) <= 0.5 ? 2 : 1};pointer-events:${flat ? 'auto' : 'none'};`
}

export function cubeGesture(face, x, y, time) {
  return { face, x, y, lastX: x, lastTime: time, velocity: 0, axis: '', position: face }
}

export function moveCubeGesture(gesture, x, y, time, width) {
  const dx = x - gesture.x, dy = y - gesture.y
  if (!gesture.axis) {
    // Ignore small sideways jitter, and give ambiguous diagonals to scrolling.
    // Once chosen, the axis stays locked until the finger lifts.
    if (Math.abs(dx) >= 16 && Math.abs(dx) > Math.abs(dy) * 1.75) gesture.axis = 'horizontal'
    else if (Math.abs(dy) >= 8) gesture.axis = 'vertical'
  }
  const elapsed = time - gesture.lastTime
  if (elapsed > 0) gesture.velocity = (x - gesture.lastX) / elapsed
  gesture.lastX = x; gesture.lastTime = time
  if (gesture.axis === 'horizontal') gesture.position = clamp(gesture.face - dx / Math.max(1, width))
  return gesture
}

export function cubeDestination(gesture, width, time) {
  // Commit after 30% of the screen in either direction, retaining natural
  // finger tracking. A flick can advance sooner; a pause drops old velocity.
  const velocity = time - gesture.lastTime < 100 ? gesture.velocity : 0
  const projected = clamp(gesture.position - velocity * 160 / Math.max(1, width))
  const progress = gesture.face === 0 ? projected : 1 - projected
  return progress >= 0.30 ? 1 - gesture.face : gesture.face
}

export function matchingScroll({ scrollTop, origin, nextOrigin, rowHeight, count }) {
  if (scrollTop < origin || !count) return Math.min(scrollTop, nextOrigin)
  const index = Math.min(count - 1, Math.max(0, Math.ceil((scrollTop - origin) / rowHeight)))
  return nextOrigin + index * rowHeight
}
