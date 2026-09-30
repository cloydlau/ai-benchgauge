import Foundation

public enum CCSwitchState: String, Codable, CaseIterable, Sendable {
    case notInstalled
    case installedEmpty
    case configured
}

public struct AppConfiguration: Decodable, Equatable, Sendable {
    public var previewCCSwitchState: CCSwitchState?

    public init(previewCCSwitchState: CCSwitchState? = nil) {
        self.previewCCSwitchState = previewCCSwitchState
    }

    public static func load(from url: URL?) -> AppConfiguration {
        guard let url, let data = try? Data(contentsOf: url),
              let configuration = try? JSONDecoder().decode(Self.self, from: data) else {
            return .init()
        }
        return configuration
    }

    /// Preview overrides the real install and providers before quota loading.
    public func ccSwitchState(isInstalled: Bool, hasProviders: Bool) -> CCSwitchState {
        previewCCSwitchState ?? (isInstalled ? (hasProviders ? .configured : .installedEmpty) : .notInstalled)
    }
}
