import Foundation
import Combine
import LeaderboardKit

@MainActor
public final class LeaderboardPadStore: ObservableObject {
    @Published public private(set) var snapshot: LeaderboardSnapshot
    @Published public private(set) var failures: [LeaderboardKind: LeaderboardFailure] = [:]
    @Published public private(set) var refreshing: Set<LeaderboardKind> = []
    @Published public var category: LeaderboardCategory { didSet { CategoryPreference.save(category, to: defaults) } }
    @Published public var grouping: LeaderboardGrouping { didSet { GroupingPreference.save(grouping, to: defaults) } }
    @Published public var language: AppLanguage { didSet { language.save(to: defaults) } }
    @Published private var filters: [LeaderboardKind: OrganizationCountry] = [:]
    private var attempts: [LeaderboardKind: Date] = [:]
    private let defaults: UserDefaults
    private let cache: LeaderboardCache?
    private let service: LeaderboardService

    public init(defaults: UserDefaults = .standard, cache: LeaderboardCache? = nil,
                service: LeaderboardService = LeaderboardService()) {
        self.defaults = defaults
        self.cache = cache ?? (try? LeaderboardCache(fileURL: LeaderboardCache.defaultFileURL()))
        self.service = service
        self.snapshot = self.cache?.load() ?? LeaderboardSnapshot()
        self.category = CategoryPreference.load(from: defaults)
        self.grouping = GroupingPreference.load(from: defaults)
        self.language = AppLanguage.load(from: defaults)
        for kind in LeaderboardKind.allCases {
            if let raw = defaults.string(forKey: "country.\(kind.rawValue)"), let country = OrganizationCountry(rawValue: raw) {
                filters[kind] = country
            }
        }
    }

    public func country(for kind: LeaderboardKind) -> OrganizationCountry? { filters[kind] }
    public func setCountry(_ country: OrganizationCountry?, for kind: LeaderboardKind) {
        filters[kind] = country
        defaults.set(country?.rawValue, forKey: "country.\(kind.rawValue)")
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
        let result = await service.refresh(kinds, keeping: LeaderboardSnapshot())
        for kind in kinds {
            if let board = result.snapshot.boards[kind] { snapshot.boards[kind] = board }
            failures[kind] = result.failures[kind]
        }
        cache?.save(snapshot)
        refreshing.subtract(kinds)
    }
}
