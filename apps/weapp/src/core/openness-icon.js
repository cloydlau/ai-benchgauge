export const opennessColors = {
  open: { light: '#188966', dark: '#77d9a1' },
  closed: { light: '#6b7280', dark: '#b8bec7' },
}
export const opennessColor = (state, dark = false) => opennessColors[state]?.[dark ? 'dark' : 'light'] || '#9399a3'

export const opennessIcon = (state, dark = false) => ['open', 'closed'].includes(state)
  ? `/assets/openness/${state}-${dark ? 'dark' : 'light'}.png` : ''
