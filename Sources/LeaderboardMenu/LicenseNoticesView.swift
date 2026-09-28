import SwiftUI
import LeaderboardCore

enum LicenseSection: Int, Identifiable {
    case application, thirdParty
    var id: Int { rawValue }
}

@MainActor
private final class LicenseSelection: ObservableObject {
    @Published var section: LicenseSection
    init(_ section: LicenseSection) { self.section = section }
}

struct LicenseDocument: Decodable, Identifiable {
    let id: String
    let name: String
    let license: String
    let source: URL
    let englishDescription: String
    let chineseDescription: String
    let file: String

    static let application = LicenseDocument(
        id: "ai-benchgauge", name: "AI BenchGauge", license: "MIT",
        source: URL(string: "https://github.com/cloydlau/ai-benchgauge")!,
        englishDescription: "Application license", chineseDescription: "本软件的许可证",
        file: "AI-BenchGauge.txt"
    )
}

/// The packaged app uses its own Resources directory; `swift run` uses the
/// SwiftPM resource bundle. Both carry the complete notices, without a network request.
enum LicenseCatalog {
    static func resource(_ file: String) -> URL? {
        if let directory = Bundle.main.resourceURL?.appendingPathComponent("Licenses"),
           FileManager.default.fileExists(atPath: directory.path) {
            let url = directory.appendingPathComponent(file)
            return FileManager.default.fileExists(atPath: url.path) ? url : nil
        }
        return Bundle.module.url(forResource: file, withExtension: nil, subdirectory: "Licenses")
    }

    static var thirdParty: [LicenseDocument]? {
        guard let url = resource("ThirdParty.json"), let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode([LicenseDocument].self, from: data)
    }

    static func text(for document: LicenseDocument) -> String? {
        guard let url = resource(document.file) else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }
}

struct LicenseNoticesView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var selection: LicenseSelection
    let language: AppLanguage

    init(section: LicenseSection, language: AppLanguage) {
        _selection = StateObject(wrappedValue: LicenseSelection(section))
        self.language = language
    }

    private func tr(_ english: String, _ chinese: String) -> String {
        language.text(english, chinese)
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                Text(tr("Licenses & notices", "许可证与声明"))
                    .font(.title3.weight(.semibold))
                Picker(tr("License section", "许可证分类"), selection: $selection.section) {
                    Text(tr("Application license", "本软件许可")).tag(LicenseSection.application)
                    Text(tr("Open-source notices", "开源软件声明")).tag(LicenseSection.thirdParty)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if selection.section == .application {
                        documentView(.application)
                    } else if let documents = LicenseCatalog.thirdParty {
                        if documents.isEmpty {
                            Text(tr(
                                "No third-party open-source code libraries are bundled with this application.",
                                "本应用目前未打包第三方开源代码库。"
                            ))
                            .foregroundStyle(.secondary)
                        } else {
                            ForEach(documents) { document in
                                documentView(document)
                            }
                        }
                    } else {
                        unavailableNotice
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
            }
            Divider()
            HStack {
                Spacer()
                Button(tr("Done", "完成")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .frame(width: 560, height: 520)
        .onExitCommand { dismiss() }
    }

    private func documentView(_ document: LicenseDocument) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(document.name)
                    .font(.headline)
                Spacer()
                Text(document.license)
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.quaternary, in: Capsule())
            }
            Text(tr(document.englishDescription, document.chineseDescription))
                .font(.callout)
                .foregroundStyle(.secondary)
            Link(tr("Project source", "项目源码"), destination: document.source)
                .font(.callout)
                .pointingHandCursor()
            if let text = LicenseCatalog.text(for: document) {
                Text(text)
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                unavailableNotice
            }
        }
    }

    private var unavailableNotice: some View {
        Text(tr("The license notice could not be loaded.", "无法读取许可证声明。"))
            .foregroundStyle(.secondary)
    }
}
