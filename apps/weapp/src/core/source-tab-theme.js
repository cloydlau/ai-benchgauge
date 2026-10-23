import catalog from '../../../../Sources/LeaderboardKit/Resources/SourceTabThemes.json' with { type: 'json' }

const sources = new Map(catalog.sources.flatMap(source => source.kinds.map(kind => [kind, source])))

export function sourceTabTheme(kind, dark) {
  return (sources.get(kind) || catalog.fallback)[dark ? 'dark' : 'light']
}
