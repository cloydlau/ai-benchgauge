import SwiftUI
import LeaderboardKit

private struct SourceRow: Identifiable {
    let id: String
    let items: [PadAboutContent.Source]
}

@MainActor
private final class PadAboutState: ObservableObject {
    // Command Line Tools do not ship SwiftUIMacros, so this stays an
    // ObservableObject instead of @State, matching the rest of the pad UI.
    @Published var expandedGroups: Set<String> = []
    @Published var noticeExpanded = false
    @Published var modelsDevNoticeExpanded = false
    @Published var licenseSourceID: String?
}

@MainActor
struct PadAboutView<Brand: View>: View {
    let language: AppLanguage
    let brand: Brand
    let copyLink: (String) -> Void
    let dismiss: () -> Void
    private let content = PadAboutContent.load()
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @StateObject private var about = PadAboutState()

    private var dark: Bool { colorScheme == .dark }
    private var outline: Color { Color.primary.opacity(dark ? 0.07 : 0.065) }
    private var inset: Color { BrandTheme.surface(for: colorScheme) }
    private var accent: Color { BrandTheme.accent(for: colorScheme) }
    private var columns: [GridItem] { Array(repeating: GridItem(.flexible(), spacing: 8), count: dynamicTypeSize.isAccessibilitySize ? 1 : 2) }
    private var sourceColumnCount: Int { dynamicTypeSize.isAccessibilitySize ? 1 : 3 }
    private func sourceRows(_ sources: [PadAboutContent.Source]) -> [SourceRow] {
        let count = sourceColumnCount
        return stride(from: 0, to: sources.count, by: count).map { start in
            let items = Array(sources[start..<min(start + count, sources.count)])
            return SourceRow(id: items.map(\.id).joined(separator: "-"), items: items)
        }
    }
    private func tr(_ en: String, _ zh: String) -> String { language.text(en, zh) }

    var body: some View {
        NavigationStack {
            ScrollView {
                if let content {
                    main(content, copy: content.copy(language: language))
                        .frame(maxWidth: 560).frame(maxWidth: .infinity)
                        .padding(.horizontal, 14).padding(.bottom, 24)
                } else {
                    ContentUnavailableView(tr("About unavailable", "暂时无法读取关于信息"), systemImage: "info.circle")
                }
            }
            .accessibilityIdentifier("about-scroll")
            .background {
                Color.padBackground
                RadialGradient(colors: [accent.opacity(0.055), .clear], center: .topTrailing,
                               startRadius: 0, endRadius: 360)
            }
            .navigationTitle(tr("About", "关于"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(tr("Done", "完成"), action: dismiss) } }
        }
        .tint(accent)
        .accessibilityIdentifier("about-page")
        .accessibilityHidden(about.licenseSourceID != nil)
        .overlay {
            if let sourceID = about.licenseSourceID {
                licenseDialog(sourceID)
            }
        }
    }

    private func main(_ content: PadAboutContent, copy: PadAboutContent.Copy) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            hero(copy.descriptionLines)
            quota(content.desktopDownloadURL)
            Text(tr("Data sources", "数据来源")).font(.system(size: 14, weight: .semibold))
                .padding(.leading, 4).padding(.top, 17).padding(.bottom, 11)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(sourceRows(content.sources)) { row in
                    // fixedSize keeps the row at the tallest card instead of stretching through the scroll view.
                    HStack(alignment: .top, spacing: 6) {
                        ForEach(row.items) { source in
                            sourceCard(source)
                        }
                    }.fixedSize(horizontal: false, vertical: true)
                }
            }
            investment(copy.investment, months: content.schedule.months(at: Date()))
                .padding(14).aboutCard(outline: outline).padding(.top, 14)
            notices(content.desktopDownloadURL).padding(.horizontal, 4).padding(.top, 17)
        }
    }
    private func hero(_ lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .bottom, spacing: 4) { brand; version }
                VStack(alignment: .leading, spacing: 6) { brand; version }
            }
            VStack(alignment: .leading, spacing: 3) {
                ForEach(lines, id: \.self) { Text($0).fixedSize(horizontal: false, vertical: true) }
            }
            .font(.system(size: 13)).lineSpacing(5).foregroundStyle(.secondary).padding(.top, 14)
            HStack(spacing: 3) {
                Capsule().fill(accent).frame(width: 20, height: 2.5)
                Capsule().fill(accent.opacity(0.55)).frame(width: 11, height: 2.5)
            }.padding(.top, 13).accessibilityHidden(true)
        }.padding(.horizontal, 4).padding(.top, 24).padding(.bottom, 17)
    }
    private var version: some View {
        Text("v" + (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""))
            .font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
            .padding(.horizontal, 5).padding(.vertical, 2.5)
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(outline, lineWidth: 0.5))
            .fixedSize().accessibilityIdentifier("about-version")
    }
    private func quota(_ url: String) -> some View {
        Button { copyLink(url) } label: {
            HStack(spacing: 10) {
                Image(systemName: "desktopcomputer").font(.system(size: 15))
                    .frame(width: 28, height: 28).background(Color.padCard, in: RoundedRectangle(cornerRadius: 8))
                Text(tr("Quota lookup", "余量查询")).font(.system(size: 14, weight: .semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(tr("PC", "PC 端")).font(.system(size: 12))
                Image(systemName: "link").font(.system(size: 13))
            }.foregroundStyle(accent).padding(.horizontal, 12).padding(.vertical, 11)
                .frame(minHeight: 50)
                .background(accent.opacity(dark ? 0.16 : 0.08), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(accent.opacity(0.12), lineWidth: 0.5))
                .contentShape(RoundedRectangle(cornerRadius: 12))
        }.buttonStyle(.plain).accessibilityIdentifier("desktop-download")
            .accessibilityLabel(tr("Quota lookup · PC · Copy link", "余量查询 · PC 端 · 复制链接"))
    }
    private func sourceCard(_ source: PadAboutContent.Source) -> some View {
        let mark = source.id == "artificialAnalysis" ? "AA" : source.id == "arena" ? "A" : "E"
        let color: Color = source.id == "artificialAnalysis" ? .blue : source.id == "arena" ? .purple : .cyan
        let showsLicense = source.id == "arena" || source.id == "epoch"
        // Wide accessibility cards fit on one line; the three-column row reserves two for the long name and domain.
        let titleLines = dynamicTypeSize.isAccessibilitySize ? 1 : 2
        let domainLines = dynamicTypeSize.isAccessibilitySize ? 1 : 2
        return VStack(alignment: .leading, spacing: 6) {
            Button { copyLink(source.url) } label: {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text(mark).font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(color)
                            .frame(width: 24, height: 24)
                            .background(color.opacity(0.09), in: RoundedRectangle(cornerRadius: 7))
                        Spacer()
                        Image(systemName: "link").font(.system(size: 12)).foregroundStyle(.secondary)
                    }.frame(height: 24).padding(.bottom, 9)
                    slottedText(source.title, size: 13, weight: .semibold, lines: titleLines, color: .primary, scale: 0.8)
                    slottedText(source.domain, size: 10, weight: .regular, lines: domainLines, color: .secondary, scale: 0.7)
                        .padding(.top, 4)
                }.frame(maxWidth: .infinity, alignment: .topLeading).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityIdentifier("about-source-" + source.id)
                .accessibilityLabel(source.title + " · " + tr("Copy link", "复制链接"))
            // Same-height slot. Not a button, so Artificial Analysis stays out of the license identifier.
            if showsLicense {
                Button { about.licenseSourceID = source.id } label: {
                    Text("CC BY 4.0").font(.system(size: 11, weight: .medium)).foregroundStyle(accent)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }.buttonStyle(.plain).frame(maxWidth: .infinity, minHeight: 28, maxHeight: 28, alignment: .leading)
                    .accessibilityIdentifier("about-license-" + source.id)
                    .accessibilityLabel(source.title + " · CC BY 4.0 · " + tr("View license", "查看协议"))
            } else {
                Color.clear.frame(maxWidth: .infinity, minHeight: 28, maxHeight: 28).accessibilityHidden(true)
            }
        }.padding(9)
            // maxHeight stretches the card chrome to the row. fixedSize on the row keeps that height finite.
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .aboutCard(outline: outline)
    }
    /// Reserves an exact line count so short labels do not shrink the card.
    /// The placeholder owns the height; wrapping text is overlaid and cannot grow one card.
    private func slottedText(_ text: String, size: CGFloat, weight: Font.Weight, lines: Int, color: Color, scale: CGFloat) -> some View {
        let placeholder = Array(repeating: " ", count: max(lines, 1)).joined(separator: "\n")
        return Text(placeholder)
            .font(.system(size: size, weight: weight))
            .lineLimit(lines)
            .hidden()
            .accessibilityHidden(true)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .overlay(alignment: .topLeading) {
                Text(text).font(.system(size: size, weight: weight)).foregroundStyle(color)
                    .lineLimit(lines).minimumScaleFactor(scale)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
    }
    private func investment(_ investment: PadAboutContent.Investment, months: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(investment.title).font(.system(size: 15, weight: .semibold)).padding(.bottom, 11)
            Text(investment.engineeringTitle).font(.system(size: 12)).foregroundStyle(.secondary)
            LazyVGrid(columns: columns, spacing: 7) {
                ForEach(investment.metrics) { metric in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(metric.value).font(.system(size: 24, weight: .semibold)).monospacedDigit()
                            .minimumScaleFactor(0.7).lineLimit(1)
                        Text(metric.label).font(.system(size: 11)).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(11)
                        .background(inset, in: RoundedRectangle(cornerRadius: 8))
                        .accessibilityElement(children: .contain).accessibilityIdentifier("about-metric-" + metric.id)
                }
            }.padding(.vertical, 9)
            note(investment.note)
            Divider().padding(.top, 14).padding(.bottom, 13)
            Text(investment.budgetTitle).font(.system(size: 12)).foregroundStyle(.secondary)
            note(investment.budgetIntro).padding(.top, 5).padding(.bottom, 8)
            ForEach(investment.groups) { group in
                costGroup(group, months: months)
                if group.id != investment.groups.last?.id { Divider() }
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(investment.totalTitle).font(.system(size: 12, weight: .medium))
                Spacer(minLength: 0)
                Text(PadAboutContent.money(investment.total(months: months), language: language))
                    .font(.system(size: 17, weight: .semibold)).foregroundStyle(accent).monospacedDigit()
                    .accessibilityIdentifier("about-cost-total")
            }.padding(11).background(accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 8)).padding(.top, 10)
            note(investment.costNote).padding(.top, 9)
        }
    }
    private func costGroup(_ group: PadAboutContent.Investment.Group, months: Int) -> some View {
        let expanded = about.expandedGroups.contains(group.id)
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) {
                    if expanded { about.expandedGroups.remove(group.id) } else { about.expandedGroups.insert(group.id) }
                }
            } label: {
                HStack(spacing: 8) {
                    Text(group.title).frame(maxWidth: .infinity, alignment: .leading)
                    Text(PadAboutContent.money(group.amount(months: months), language: language)).monospacedDigit()
                    Image(systemName: expanded ? "chevron.up" : "chevron.down").font(.system(size: 9)).foregroundStyle(.secondary)
                }.font(.system(size: 13)).foregroundStyle(.primary).frame(minHeight: 48).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityIdentifier("about-cost-" + group.id)
                .accessibilityValue(expanded ? tr("Expanded", "已展开") : tr("Collapsed", "已收起"))
            if expanded {
                ForEach(group.items) { item in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(item.title).frame(maxWidth: .infinity, alignment: .leading)
                            Text(PadAboutContent.money(item.amount(months: months), language: language)).foregroundStyle(.secondary).monospacedDigit()
                        }.font(.system(size: 12))
                        note(item.body)
                    }.padding(.top, 7).padding(.bottom, 6)
                        .accessibilityElement(children: .contain).accessibilityIdentifier("about-cost-item-" + item.id)
                }
            }
        }.padding(.horizontal, 7).padding(.bottom, expanded ? 10 : 0)
            .background(expanded ? inset : .clear, in: RoundedRectangle(cornerRadius: 7))
    }
    private func notices(_ url: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider().padding(.bottom, 5)
            ViewThatFits(in: .horizontal) {
                HStack { noticeTitle; Spacer(); contribute(url) }
                VStack(alignment: .leading, spacing: 0) { noticeTitle; contribute(url) }
            }
            note(tr("Third-party software and data follow their original licenses. Tap to read the full copyright and license text.", "第三方软件及数据分别遵循其原始许可证。点按查看完整版权与许可文本。"))
            Button {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) { about.modelsDevNoticeExpanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Text(tr("Third-party notice 01", "第三方软件声明 01")).font(.system(size: 12))
                    Text("MIT").font(.system(size: 10)).foregroundStyle(.secondary).padding(4)
                        .background(inset, in: RoundedRectangle(cornerRadius: 3))
                    Spacer(minLength: 0)
                    Image(systemName: about.modelsDevNoticeExpanded ? "chevron.up" : "chevron.down").font(.system(size: 10)).foregroundStyle(.secondary)
                }.foregroundStyle(.primary).frame(minHeight: 48).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityIdentifier("models-dev-license")
                .accessibilityValue(about.modelsDevNoticeExpanded ? tr("Expanded", "已展开") : tr("Collapsed", "已收起"))
            if about.modelsDevNoticeExpanded {
                Text(ModelsDevAttribution.licenseText).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                    .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    .padding(10).aboutCard(outline: outline).accessibilityIdentifier("models-dev-license-text")
            }
            Button {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) { about.noticeExpanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Text(tr("Third-party notice 02", "第三方软件声明 02")).font(.system(size: 12))
                    Text("SIL OFL 1.1").font(.system(size: 10)).foregroundStyle(.secondary).padding(4)
                        .background(inset, in: RoundedRectangle(cornerRadius: 3))
                    Spacer(minLength: 0)
                    Image(systemName: about.noticeExpanded ? "chevron.up" : "chevron.down").font(.system(size: 10)).foregroundStyle(.secondary)
                }.foregroundStyle(.primary).frame(minHeight: 48).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityIdentifier("open-source-notices")
                .accessibilityValue(about.noticeExpanded ? tr("Expanded", "已展开") : tr("Collapsed", "已收起"))
            if about.noticeExpanded {
                Text(BrandFont.licenseText).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                    .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    .padding(10).aboutCard(outline: outline).accessibilityIdentifier("about-license-text")
            }
        }
    }
    private var noticeTitle: some View { Text(tr("Third-party licenses", "第三方许可")).font(.system(size: 14, weight: .semibold)) }
    private func contribute(_ url: String) -> some View {
        Button { copyLink(url) } label: {
            HStack(spacing: 5) { Text(tr("Contribute code", "贡献代码")).underline(); Image(systemName: "link") }
                .font(.system(size: 12)).frame(minHeight: 44)
        }.buttonStyle(.plain).foregroundStyle(accent).accessibilityIdentifier("about-contribute")
    }
    private func note(_ text: String) -> some View {
        Text(text).font(.system(size: 11)).lineSpacing(4).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
    private func licenseDialog(_ sourceID: String) -> some View {
        // Arena and Epoch share one official deed. Attribution notices stay on source help and exports.
        let notice = CCBYLicense.text(language: language)
        return ZStack {
            Color.black.opacity(dark ? 0.48 : 0.32).ignoresSafeArea()
                .onTapGesture { about.licenseSourceID = nil }
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 12) {
                Text("CC BY 4.0").font(.system(size: 16, weight: .semibold))
                    .accessibilityIdentifier("about-license-dialog-" + sourceID)
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(notice.components(separatedBy: "\n\n").enumerated()), id: \.offset) { _, paragraph in
                            licenseParagraph(paragraph)
                        }
                    }
                }.frame(maxHeight: dynamicTypeSize.isAccessibilitySize ? 360 : 440)
                Button(tr("Got it", "知道了")) { about.licenseSourceID = nil }
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(accent)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(accent.opacity(dark ? 0.16 : 0.08), in: RoundedRectangle(cornerRadius: 10))
                    .accessibilityIdentifier("about-license-dismiss")
            }
            .padding(16).frame(maxWidth: 440)
            .background(Color.padCard, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(outline, lineWidth: 0.5))
            .shadow(color: .black.opacity(0.12), radius: 18, y: 6)
            .padding(.horizontal, 28)
        }
    }

    @ViewBuilder
    private func licenseParagraph(_ paragraph: String) -> some View {
        let body = Text(paragraph).font(.system(size: 13)).lineSpacing(4).foregroundStyle(.secondary)
            .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        // Keep the section heading separately identifiable; the full deed is too long for one accessibility label.
        if paragraph.contains("Section 1") || paragraph.contains("第一条") || paragraph.contains("第1條") {
            body.accessibilityIdentifier("about-license-notice")
        } else {
            body
        }
    }
}

private extension View {
    func aboutCard(outline: Color) -> some View {
        background(Color.padCard, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(outline, lineWidth: 0.5))
            .shadow(color: .black.opacity(0.035), radius: 7, y: 2)
    }
}
