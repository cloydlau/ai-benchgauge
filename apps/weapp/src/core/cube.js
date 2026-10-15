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
  if (!gesture.axis && Math.max(Math.abs(dx), Math.abs(dy)) >= 9) {
    gesture.axis = Math.abs(dx) > Math.abs(dy) * 1.25 ? 'horizontal' : 'vertical'
  }
  const elapsed = time - gesture.lastTime
  if (elapsed > 0) gesture.velocity = (x - gesture.lastX) / elapsed
  gesture.lastX = x; gesture.lastTime = time
  if (gesture.axis === 'horizontal') gesture.position = clamp(gesture.face - dx / Math.max(1, width))
  return gesture
}

export function cubeDestination(gesture, width, time) {
  // A short fast flick advances; a slow short drag returns. A pause before
  // release discards the old velocity instead of surprising the user.
  const velocity = time - gesture.lastTime < 100 ? gesture.velocity : 0
  return clamp(gesture.position - velocity * 160 / Math.max(1, width)) >= 0.5 ? 1 : 0
}

export function matchingScroll({ scrollTop, origin, nextOrigin, rowHeight, count }) {
  if (scrollTop < origin || !count) return Math.min(scrollTop, nextOrigin)
  const index = Math.min(count - 1, Math.max(0, Math.ceil((scrollTop - origin) / rowHeight)))
  return nextOrigin + index * rowHeight
}
