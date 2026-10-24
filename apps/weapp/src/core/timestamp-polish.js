export const polishDuration = 1100
export const polishInterval = 30000

// One visible timestamp, with no ticking timer during loading or page hiding.
export function createTimestampPolish(change, { later = setTimeout, cancel = clearTimeout } = {}) {
  let kind = null, ready = false, next, finish
  function clear() { cancel(next); cancel(finish); change(null) }
  function sweep() {
    change(kind)
    finish = later(() => change(null), polishDuration)
    next = later(sweep, polishInterval)
  }
  return {
    update(nextKind, nextReady) {
      if (kind === nextKind && ready === nextReady) return
      clear(); kind = nextKind; ready = nextReady
      if (ready) sweep()
    },
    stop() { clear(); kind = null; ready = false },
  }
}
