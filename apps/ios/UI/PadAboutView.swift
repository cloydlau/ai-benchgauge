import SwiftUI
import ImageIO
import LeaderboardKit

@MainActor
private enum SourceIconCache {
    static let images: [String: CGImage] = ["cloudbase", "vercel", "openRouter", "artificialAnalysis", "arena", "epoch"]
        .flatMap { [$0, $0 + "-dark"] }.reduce(into: [:]) { images, name in
            guard let url = Bundle.module.url(forResource: name, withExtension: "png", subdirectory: "SourceLogos"),
                  let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return }
            images[name] = image
        }
}

@MainActor
struct SourceBrandIcon: View {
    let sourceID: String
    let dark: Bool
    var size: CGFloat = 24

    var body: some View {
        if let icon = SourceIconCache.images[sourceID + (dark ? "-dark" : "")] {
            Image(decorative: icon, scale: 3).renderingMode(.original)
                .resizable().scaledToFit().frame(width: size, height: size)
                .accessibilityHidden(true)
        }
    }
}

@MainActor
private final class PadAboutState: ObservableObject {
    // Command Line Tools do not ship SwiftUIMacros, so this stays an
    // ObservableObject instead of @State, matching the rest of the pad UI.
    @Published var expandedGroups: Set<String> = []
    @Published var noticeExpanded = false
    @Published var modelsDevNoticeExpanded = false
    @Published var categoryIconNoticeExpanded = false
    @Published var sourceMarkNoticeExpanded = false
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
    }

    private func main(_ content: PadAboutContent, copy: PadAboutContent.Copy) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            hero(copy.descriptionLines)
            platforms(copy.platforms)
            investment(copy.investment, months: content.schedule.months(at: Date()))
                .padding(14).aboutCard(outline: outline).padding(.top, 14)
            notices.padding(.horizontal, 4).padding(.top, 17)
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
    private func platformTint(_ status: String) -> Color {
        status == "live" ? .green : status == "development" ? .orange : .secondary
    }
    private func platforms(_ content: PadAboutContent.Platforms) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(content.title).font(.system(size: 15, weight: .semibold)).padding(.vertical, 12)
            ForEach(content.items) { platform in
                Divider()
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(platform.name).font(.system(size: 14, weight: .medium))
                        if !platform.featureText.isEmpty {
                            Text(platform.featureText).font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                    }.fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
                    VStack(alignment: .trailing, spacing: 0) {
                        if platform.status == "live", let url = platform.url {
                            Button { copyLink(url) } label: {
                                HStack(spacing: 3) {
                                    platformStatus(platform)
                                    Image(systemName: "link").font(.system(size: 10))
                                }.frame(minHeight: 36).contentShape(Rectangle())
                            }.buttonStyle(.plain).foregroundStyle(platformTint(platform.status))
                                .accessibilityIdentifier("about-platform-download-" + platform.id)
                                .accessibilityLabel(platform.name + " · " + platform.statusLabel + " · " + content.downloadLabel)
                        } else {
                            platformStatus(platform)
                        }
                        if platform.prWelcome, let url = platform.url {
                            Button { copyLink(url) } label: {
                                HStack(spacing: 3) {
                                    Text(content.prWelcomeLabel)
                                    Image(systemName: "link").font(.system(size: 9))
                                }.font(.system(size: 11)).frame(minHeight: 36).contentShape(Rectangle())
                            }.buttonStyle(.plain).foregroundStyle(accent)
                                .accessibilityIdentifier("about-platform-pr-" + platform.id)
                                .accessibilityLabel(platform.name + " · " + content.prWelcomeLabel + " · " + content.copyLinkLabel)
                        }
                    }.fixedSize(horizontal: !dynamicTypeSize.isAccessibilitySize, vertical: true)
                }.padding(.vertical, 7).frame(minHeight: 52)
                    .accessibilityElement(children: .contain).accessibilityIdentifier("about-platform-" + platform.id)
            }
            Divider()
            Button { copyLink(content.repositoryURL) } label: {
                HStack {
                    Text(content.contributeLabel).underline()
                    Spacer()
                    Image(systemName: "link")
                }.font(.system(size: 12)).frame(minHeight: 48).contentShape(Rectangle())
            }.buttonStyle(.plain).foregroundStyle(accent).accessibilityIdentifier("about-contribute")
                .accessibilityLabel(content.contributeLabel + " · " + content.copyLinkLabel)
        }.padding(.horizontal, 12).aboutCard(outline: outline)
            .accessibilityElement(children: .contain).accessibilityIdentifier("about-platforms")
    }
    private func platformStatus(_ platform: PadAboutContent.Platforms.Platform) -> some View {
        Text(platform.statusLabel).font(.system(size: 10, weight: .medium))
            .padding(.horizontal, 6).padding(.vertical, 3)
            .foregroundStyle(platformTint(platform.status))
            .background(platformTint(platform.status).opacity(dark ? 0.16 : 0.08), in: RoundedRectangle(cornerRadius: 4))
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("about-platform-status-" + platform.id)
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
    private var notices: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider().padding(.bottom, 5)
            noticeTitle
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
            Button {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) { about.categoryIconNoticeExpanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Text(tr("Third-party notice 03", "第三方软件声明 03")).font(.system(size: 12))
                    Text("MIT").font(.system(size: 10)).foregroundStyle(.secondary).padding(4)
                        .background(inset, in: RoundedRectangle(cornerRadius: 3))
                    Spacer(minLength: 0)
                    Image(systemName: about.categoryIconNoticeExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }.foregroundStyle(.primary).frame(minHeight: 48).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityIdentifier("category-icons-license")
                .accessibilityValue(about.categoryIconNoticeExpanded ? tr("Expanded", "已展开") : tr("Collapsed", "已收起"))
            if about.categoryIconNoticeExpanded,
               let licenseURL = Bundle.module.url(forResource: "LICENSE", withExtension: "txt", subdirectory: "CategoryIcons"),
               let license = try? String(contentsOf: licenseURL, encoding: .utf8) {
                Text(license).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                    .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    .padding(10).aboutCard(outline: outline).accessibilityIdentifier("category-icons-license-text")
            }
            Button {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) { about.sourceMarkNoticeExpanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Text(tr("Source brand marks", "来源品牌标识")).font(.system(size: 12))
                    Text(tr("Trademarks", "商标")).font(.system(size: 10)).foregroundStyle(.secondary).padding(4)
                        .background(inset, in: RoundedRectangle(cornerRadius: 3))
                    Spacer(minLength: 0)
                    Image(systemName: about.sourceMarkNoticeExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }.foregroundStyle(.primary).frame(minHeight: 48).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityIdentifier("source-marks-notice")
                .accessibilityValue(about.sourceMarkNoticeExpanded ? tr("Expanded", "已展开") : tr("Collapsed", "已收起"))
            if about.sourceMarkNoticeExpanded,
               let url = Bundle.module.url(forResource: "NOTICE", withExtension: "txt", subdirectory: "SourceLogos"),
               let notice = try? String(contentsOf: url, encoding: .utf8) {
                Text(notice).font(.system(size: 11)).foregroundStyle(.secondary)
                    .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    .padding(10).aboutCard(outline: outline)
            }
        }
    }
    private var noticeTitle: some View { Text(tr("Third-party licenses", "第三方许可")).font(.system(size: 14, weight: .semibold)) }
    private func note(_ text: String) -> some View {
        Text(text).font(.system(size: 11)).lineSpacing(4).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private extension View {
    func aboutCard(outline: Color) -> some View {
        background(Color.padCard, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(outline, lineWidth: 0.5))
            .shadow(color: .black.opacity(0.035), radius: 7, y: 2)
    }
}
