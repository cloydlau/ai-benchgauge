#if canImport(SwiftUI)
import SwiftUI

@MainActor
private final class CountryHelpState: ObservableObject {
    @Published var showingExplanation = false
}

public struct UnknownCountryButton: View {
    private let language: AppLanguage
    @StateObject private var state = CountryHelpState()

    public init(language: AppLanguage) { self.language = language }

    public var body: some View {
        Button { state.showingExplanation = true } label: {
            Image(systemName: "questionmark.circle")
                .font(.system(size: 13)).foregroundStyle(.secondary)
                .frame(minWidth: 24, minHeight: 24).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(OrganizationRegion.unknownTitle(language: language))
        .accessibilityIdentifier("unknown-country-help")
        .alert(OrganizationRegion.unknownTitle(language: language), isPresented: $state.showingExplanation) {
            Button(language.text("OK", "知道了"), role: .cancel) { }
        } message: {
            Text(OrganizationRegion.unknownExplanation(language: language))
        }
    }
}
#endif
