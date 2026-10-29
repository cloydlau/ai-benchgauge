// Display guides only for the active board; only an explicit tap records discovery.
export function createMetricGuide({ supports, read, write, show, readyNow = () => true, later = setTimeout, cancel = clearTimeout }) {
  let kind = null, pending, displayed = false
  const stop = () => { cancel(pending); pending = undefined; kind = null; displayed = false; show(null) }
  const seen = value => { try { return read().includes(value) } catch { return false } }
  const remember = value => { try { const list = read(); write([...new Set([...list, value])]) } catch { /* Optional local storage. */ } }
  return {
    update(next, ready) {
      if (!ready || !supports(next)) { stop(); return }
      if (kind === next) return
      stop()
      if (seen(next)) return
      kind = next
      pending = later(() => {
        if (kind !== next || !readyNow(next)) { stop(); return }
        displayed = true; show(next)
      }, 1000)
    },
    acknowledge(value) { if (supports(value)) remember(value); if (kind === value) stop() },
    stop,
    isDisplayed: () => displayed,
  }
}
