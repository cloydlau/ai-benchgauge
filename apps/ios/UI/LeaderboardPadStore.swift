import Foundation
import Combine
import LeaderboardKit

@MainActor
public final class LeaderboardPadStore: ObservableObject {
    @Published public private(set) var snapshot: LeaderboardSnapshot { didSet { rowPresentations.removeAll(); countryOptionsCache = nil } }
    @Published public private(set) var failures: [LeaderboardKind: LeaderboardFailure] = [:]
    @Published public private(set) var refreshing: Set<LeaderboardKind> = []
    @Published public var category: LeaderboardCategory { didSet { CategoryPreference.save(category, to: defaults) } }
    @Published public var grouping: LeaderboardGrouping { didSet { rowPresentations.removeAll(); GroupingPreference.save(grouping, to: defaults) } }
    @Published public var appearance: String { didSet { defaults.set(appearance, forKey: "mobileAppearance") } }
    @Published public var selectedSource: Int { didSet { defaults.set(selectedSource, forKey: "mobileSelectedSource") } }
    @Published public var language: AppLanguage { didSet { rowPresentations.removeAll(); language.save(to: defaults) } }
    @Published private var filters: [LeaderboardKind: LeaderboardCountryFilter] = [:]
    @Published private var opennessFilters: [LeaderboardKind: LeaderboardOpennessFilter] = [:]
    private var attempts: [LeaderboardKind: Date] = [:]
    private let defaults: UserDefaults
    private let cache: LeaderboardCache?
    private let service: LeaderboardService
    private var rowPresentations: [LeaderboardKind: PadRowPresentation] = [:]
    private var countryOptionsCache: [LeaderboardCountryFilter]?

    func rowPresentation(for kind: LeaderboardKind) -> PadRowPresentation {
        if let cached = rowPresentations[kind] { return cached }
        let value = PadRowPresentation(board: snapshot.boards[kind], grouping: grouping,
            country: countryFilter(for: kind), openness: opennessFilter(for: kind), language: language)
        rowPresentations[kind] = value
        return value
    }

    public init(defaults: UserDefaults = .standard, cache: LeaderboardCache? = nil,
                service: LeaderboardService = LeaderboardService()) {
        self.defaults = defaults
        self.cache = cache ?? (try? LeaderboardCache(fileURL: LeaderboardCache.defaultFileURL()))
        self.service = service
        self.snapshot = self.cache?.load() ?? LeaderboardSnapshot()
        self.category = CategoryPreference.load(from: defaults)
        self.grouping = GroupingPreference.load(from: defaults)
        self.language = AppLanguage.load(from: defaults)
        self.appearance = defaults.string(forKey: "mobileAppearance") ?? "system"
        self.selectedSource = defaults.integer(forKey: "mobileSelectedSource") == 1 ? 1 : 0
        for kind in LeaderboardKind.allCases {
            if let raw = defaults.string(forKey: "openness.\(kind.rawValue)") {
                opennessFilters[kind] = LeaderboardOpennessFilter(rawValue: raw)
            }
            if let raw = defaults.string(forKey: "country.\(kind.rawValue)") {
                if raw == "unknown" { filters[kind] = .unknown }
                else if let country = OrganizationCountry(rawValue: raw) { filters[kind] = .country(country) }
            }
        }
        // Migrate the visible category's former per-board choices once. An
        // explicit global "all" must also override old saved filters.
        let legacyCountry = category.boardKinds.compactMap { filters[$0] }.first ?? .all
        let rawCountry = defaults.string(forKey: "mobileCountryFilter")
        let country: LeaderboardCountryFilter = rawCountry.map { value in
            value == "unknown" ? .unknown : OrganizationCountry(rawValue: value).map(LeaderboardCountryFilter.country) ?? .all
        } ?? legacyCountry
        let openness = defaults.string(forKey: "mobileOpennessFilter").flatMap(LeaderboardOpennessFilter.init(rawValue:))
            ?? category.boardKinds.compactMap { opennessFilters[$0] }.first ?? .all
        filters = Dictionary(uniqueKeysWithValues: LeaderboardKind.allCases.map { ($0, country) })
        opennessFilters = Dictionary(uniqueKeysWithValues: LeaderboardKind.allCases.map { ($0, openness) })
        if rawCountry == nil {
            let value: String = switch country { case .all: "all"; case .unknown: "unknown"; case .country(let region): region.rawValue }
            defaults.set(value, forKey: "mobileCountryFilter")
        }
        if defaults.string(forKey: "mobileOpennessFilter") == nil { defaults.set(openness.rawValue, forKey: "mobileOpennessFilter") }
    }

    public func country(for kind: LeaderboardKind) -> OrganizationCountry? {
        if case .country(let country) = countryFilter(for: kind) { return country }
        return nil
    }
    // Freeze an export without writing preferences or refreshing between pages.
    init(exporting source: LeaderboardPadStore) {
        defaults = source.defaults
        cache = nil
        service = LeaderboardService()
        snapshot = source.snapshot
        category = source.category
        grouping = source.grouping
        language = source.language
        appearance = source.appearance
        selectedSource = source.selectedSource
        filters = source.filters
        opennessFilters = source.opennessFilters
    }
    public func countryFilter(for kind: LeaderboardKind) -> LeaderboardCountryFilter { filters[kind] ?? .all }
    public func opennessFilter(for kind: LeaderboardKind) -> LeaderboardOpennessFilter { opennessFilters[kind] ?? .all }
    public func setOpennessFilter(_ filter: LeaderboardOpennessFilter, for kind: LeaderboardKind) {
        rowPresentations.removeAll()
        opennessFilters = Dictionary(uniqueKeysWithValues: LeaderboardKind.allCases.map { ($0, filter) })
        defaults.set(filter.rawValue, forKey: "mobileOpennessFilter")
        for source in LeaderboardKind.allCases { defaults.set(filter == .all ? nil : filter.rawValue, forKey: "openness.\(source.rawValue)") }
    }
    public func setCountryFilter(_ filter: LeaderboardCountryFilter, for kind: LeaderboardKind) {
        rowPresentations.removeAll()
        filters = Dictionary(uniqueKeysWithValues: LeaderboardKind.allCases.map { ($0, filter) })
        let value: String? = switch filter { case .all: nil; case .unknown: "unknown"; case .country(let country): country.rawValue }
        defaults.set(value ?? "all", forKey: "mobileCountryFilter")
        for source in LeaderboardKind.allCases { defaults.set(value, forKey: "country.\(source.rawValue)") }
    }
    public var availableCountryFilters: [LeaderboardCountryFilter] {
        var result = countryOptionsCache ?? [.all]
        if countryOptionsCache == nil {
            for kind in LeaderboardKind.allCases {
                for filter in LeaderboardPresentation.countryFilters(snapshot.boards[kind]) where !result.contains(filter) { result.append(filter) }
            }
            countryOptionsCache = result
        }
        if let selected = filters.values.first, !result.contains(selected) { result.append(selected) }
        return result
    }
    public func setCountry(_ country: OrganizationCountry?, for kind: LeaderboardKind) {
        setCountryFilter(country.map(LeaderboardCountryFilter.country) ?? .all, for: kind)
    }

    public func refresh(force: Bool = false, now: Date = Date()) async {
        let requested = force ? category.boardKinds : LeaderboardFreshness.dueKinds(
            category.boardKinds, snapshot: snapshot, lastAttempts: attempts, now: now)
        let kinds = requested.filter { !refreshing.contains($0) }
        guard !kinds.isEmpty else { return }
        refreshing.formUnion(kinds)
        for kind in kinds { attempts[kind] = now }
        // Another category can refresh while this one is suspended. Merge only
        // this request's successful boards so its return cannot overwrite them.
        let result = await service.refresh(kinds, keeping: LeaderboardSnapshot(), onBoard: { [weak self] board in
            await self?.accept(board)
        })
        for kind in kinds {
            if let board = result.snapshot.boards[kind], board.canReplace(snapshot.boards[kind]) { snapshot.boards[kind] = board }
            failures[kind] = result.failures[kind]
        }
        cache?.save(snapshot)
        refreshing.subtract(kinds)
    }

    private func accept(_ board: Leaderboard) {
        guard board != snapshot.boards[board.kind], board.canReplace(snapshot.boards[board.kind]) else { return }
        snapshot.boards[board.kind] = board
        failures[board.kind] = nil
        cache?.save(snapshot)
    }
}
