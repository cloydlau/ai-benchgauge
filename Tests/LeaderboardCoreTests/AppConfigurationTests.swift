import Foundation
import LeaderboardCore
import Testing

struct AppConfigurationTests {
    @Test
    func previewOverridesInstalledProviders() throws {
        for state in CCSwitchState.allCases {
            let data = Data("{\"previewCCSwitchState\":\"\(state.rawValue)\"}".utf8)
            let configuration = try JSONDecoder().decode(AppConfiguration.self, from: data)
            for installed in [false, true] {
                for providers in [false, true] {
                    #expect(configuration.ccSwitchState(isInstalled: installed, hasProviders: providers) == state)
                }
            }
        }
    }

    @Test
    func missingOrNullPreviewUsesActualState() throws {
        for json in ["{}", "{\"previewCCSwitchState\":null}"] {
            let configuration = try JSONDecoder().decode(AppConfiguration.self, from: Data(json.utf8))
            #expect(configuration.ccSwitchState(isInstalled: false, hasProviders: false) == .notInstalled)
            #expect(configuration.ccSwitchState(isInstalled: true, hasProviders: false) == .installedEmpty)
            #expect(configuration.ccSwitchState(isInstalled: true, hasProviders: true) == .configured)
        }
    }

    @Test
    func loadsInstalledEmptyFromPackagedFile() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("app.json")
        try Data(#"{"version":"0.0.0","previewCCSwitchState":"installedEmpty"}"#.utf8).write(to: url)
        #expect(AppConfiguration.load(from: url).previewCCSwitchState == .installedEmpty)
        #expect(AppConfiguration.load(from: nil).previewCCSwitchState == nil)
    }
    @Test
    func testBundledPreviewStatesAndAutomaticMode() throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "app-config-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(AppConfiguration.load(from: url).previewCCSwitchState == nil)
        for state in CCSwitchState.allCases {
            try Data(#"{"previewCCSwitchState":"\#(state.rawValue)"}"#.utf8).write(to: url)
            #expect(AppConfiguration.load(from: url).previewCCSwitchState == state)
        }
        try Data(#"{"previewCCSwitchState":null}"#.utf8).write(to: url)
        #expect(AppConfiguration.load(from: url).previewCCSwitchState == nil)
    }
}
