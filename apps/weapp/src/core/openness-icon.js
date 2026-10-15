export const opennessIcon = (state, dark = false) => ['open', 'closed'].includes(state)
  ? `/assets/openness/${state}-${dark ? 'dark' : 'light'}.png` : ''
