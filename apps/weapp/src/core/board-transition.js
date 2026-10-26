import { cubeFaceStyle } from './cube.js'

export const boardTransitions = ['cube', 'slide', 'fade']
export const normalizeBoardTransition = value => boardTransitions.includes(value) ? value : 'cube'

// All styles share the same gesture, face hosts and scroll alignment. Only the
// presentation changes, so switching styles cannot change the chosen board.
export function boardFaceStyle(mode, index, position, duration = 0, active = false, origin = 0, direction = 1) {
  const distance = index - position
  const opacity = Math.max(0, 1 - Math.abs(distance))
  const reducedMotion = `--face-opacity:${opacity};`
  if (normalizeBoardTransition(mode) === 'cube') return reducedMotion + cubeFaceStyle(index, position, duration, active, origin, direction)
  const inTurn = active && (index === origin || index === origin + direction)
  const visible = inTurn || Math.abs(distance) < 0.9999
  const flat = Math.abs(distance) < 0.0001
  const transform = flat ? 'none' : mode === 'fade'
    ? `translateX(${distance * 12}px) scale(${1 - Math.min(1, Math.abs(distance)) * 0.025})`
    : `translateX(${distance * 100}%)`
  return `${reducedMotion}transform:${transform};transition-duration:${duration}ms;opacity:${visible ? mode === 'fade' ? opacity : 1 : 0};z-index:${Math.abs(distance) <= 0.5 ? 2 : 1};pointer-events:${flat ? 'auto' : 'none'};`
}
