import SwiftUI
import ImageIO
import LeaderboardKit

@MainActor
private enum SourceIconCache {
    static let images: [String: CGImage] = ["cloudbase", "vercel", "openRouter", "artificialAnalysis", "arena", "epoch", "wechat", "weibo", "solvay"]
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
    @Published var artworkExpanded = false
    @Published var artworkTitleWidth: CGFloat = 0
    @Published var selectedContributorID: String?
    @Published var hoveredContributorID: String?
    @Published var contributorsExpanded = false
}

@MainActor
private enum AboutContributorImages {
    static var images: [String: CGImage] = [:]
    static func image(for avatar: String) -> CGImage? {
        if let image = images[avatar] { return image }
        let file = (avatar as NSString).lastPathComponent as NSString
        guard !avatar.isEmpty,
              let url = Bundle.main.url(forResource: file.deletingPathExtension,
                                        withExtension: file.pathExtension, subdirectory: "logos"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        images[avatar] = image
        return image
    }
}

private struct AboutArtworkTitleWidth: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

@MainActor
private enum AboutArtworkImage {
    static let image: CGImage? = {
        guard let url = Bundle.main.url(forResource: "ai-models-group-portrait", withExtension: "jpg", subdirectory: "about"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }()
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
        .sheet(isPresented: $about.artworkExpanded) {
            if let content, let image = AboutArtworkImage.image {
                let artwork = content.copy(language: language).artwork
                NavigationStack {
                    Image(decorative: image, scale: 1).resizable().scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(.black)
                        .accessibilityLabel(artwork.alt)
                        .navigationTitle(artwork.title)
                        #if os(iOS)
                        .navigationBarTitleDisplayMode(.inline)
                        #endif
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button(tr("Done", "完成")) { about.artworkExpanded = false }
                            }
                            ToolbarItem(placement: .confirmationAction) {
                                Link(destination: artwork.sourceURL) { SourceBrandIcon(sourceID: "weibo", dark: dark, size: 18) }
                                    .accessibilityLabel(artwork.sourceLabel)
                            }
                        }
                }.tint(accent)
            }
        }
        .sheet(isPresented: $about.contributorsExpanded) {
            if let content {
                let copy = content.copy(language: language).contributors
                NavigationStack {
                    ScrollView { contributors(copy).padding(16).frame(maxWidth: 560).frame(maxWidth: .infinity) }
                        .background(Color.padBackground)
                        .navigationTitle(copy.title)
                        #if os(iOS)
                        .navigationBarTitleDisplayMode(.inline)
                        #endif
                        .toolbar { ToolbarItem(placement: .confirmationAction) {
                            Button(copy.closeLabel) { about.contributorsExpanded = false }
                        } }
                }.tint(accent)
            }
        }
    }

    private func main(_ content: PadAboutContent, copy: PadAboutContent.Copy) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            hero(copy.descriptionLines)
            artworkCard(copy.artwork).padding(.bottom, 14)
            platforms(copy.platforms)
            investment(copy.investment, months: content.schedule.months(at: Date()), contributors: copy.contributors)
                .padding(14).aboutCard(outline: outline).padding(.top, 14)
            notices.padding(.horizontal, 4).padding(.top, 17)
        }
    }
    @ViewBuilder
    private func artworkCard(_ artwork: PadAboutContent.Artwork) -> some View {
        if let image = AboutArtworkImage.image {
            VStack(alignment: .leading, spacing: 0) {
                Button { about.artworkExpanded = true } label: {
                    Image(decorative: image, scale: 1).resizable().scaledToFit()
                        .aspectRatio(artwork.width / artwork.height, contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                }.buttonStyle(.plain)
                    .accessibilityLabel(artwork.alt + " · " + artwork.previewLabel)
                    .accessibilityIdentifier("about-artwork-preview")
                HStack(alignment: .center, spacing: 12) {
                    artworkTitle(artwork)
                    artworkCredits(artwork)
                }.frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 13).padding(.vertical, 8)
            }
            .background(Color.padCard)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(outline, lineWidth: 0.5))
            .accessibilityElement(children: .contain).accessibilityIdentifier("about-artwork")
        }
    }
    private func artworkTitle(_ artwork: PadAboutContent.Artwork) -> some View {
        GeometryReader { geometry in
            artworkTitleStack(artwork, size: 20)
                .background {
                    GeometryReader { title in
                        Color.clear.preference(key: AboutArtworkTitleWidth.self, value: title.size.width)
                    }
                }
                .scaleEffect(min(1, max(0, geometry.size.width) / max(1, about.artworkTitleWidth)), anchor: .leading)
                .opacity(about.artworkTitleWidth > 0 ? 1 : 0)
        }.frame(height: 28)
            .onPreferenceChange(AboutArtworkTitleWidth.self) { width in
                if about.artworkTitleWidth != width { about.artworkTitleWidth = width }
            }
    }
    private func artworkTitleStack(_ artwork: PadAboutContent.Artwork, size: CGFloat) -> some View {
        HStack(alignment: .bottom, spacing: 4) {
            Text(artwork.title).font(.system(size: size, weight: .semibold))
                .lineLimit(1).fixedSize().frame(height: size)
            Text(artwork.caption).font(.system(size: size / 2)).foregroundStyle(.secondary)
                .lineLimit(1).fixedSize().frame(height: size / 2)
        }.fixedSize(horizontal: true, vertical: false).frame(height: 28)
    }
    private func artworkCredits(_ artwork: PadAboutContent.Artwork) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(artwork.credits) { credit in
                HStack(alignment: .center, spacing: 4) {
                    Text(credit.role).font(.system(size: 8)).foregroundStyle(.secondary)
                        .frame(width: 22, alignment: .leading)
                    Link(destination: credit.url) {
                        HStack(alignment: .center, spacing: 3) {
                            SourceBrandIcon(sourceID: credit.sourceIcon, dark: dark,
                                            size: credit.sourceIcon == "solvay" && dark ? 7 : 9)
                                .padding(credit.sourceIcon == "solvay" && dark ? 1 : 0)
                                .background(credit.sourceIcon == "solvay" && dark
                                            ? Color(red: 241 / 255, green: 238 / 255, blue: 232 / 255) : .clear,
                                            in: RoundedRectangle(cornerRadius: 1.5))
                            Text(credit.name).underline().font(.system(size: 9, weight: .medium))
                                .lineLimit(1).fixedSize()
                        }.frame(height: 14, alignment: .center).contentShape(Rectangle())
                    }.foregroundStyle(accent)
                        .accessibilityLabel(credit.role + " · " + credit.name + (credit.detail.isEmpty ? "" : " · " + credit.detail))
                        .accessibilityIdentifier("about-artwork-credit-" + credit.id)
                }
            }
        }.fixedSize()
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
                HStack(alignment: .center, spacing: 8) {
                    platformIcon(platform.id).foregroundStyle(.secondary)
                        .frame(width: 20, height: 24).accessibilityHidden(true)
                    HStack(alignment: .center, spacing: 0) {
                        Text(platform.name).font(.system(size: 12, weight: .medium))
                        if !platform.note.isEmpty {
                            Text(platform.note).font(.system(size: 9)).foregroundStyle(.secondary)
                        }
                    }
                    .lineLimit(1).minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
                    .accessibilityElement(children: .combine)
                    if !platform.featureText.isEmpty {
                        Text(platform.featureText).font(.system(size: 10)).foregroundStyle(.secondary)
                            .lineLimit(1).fixedSize()
                    }
                    platformStatus(platform).frame(width: language == .english ? 90 : 48, alignment: .trailing)
                }.frame(minHeight: 48)
                    .accessibilityElement(children: .contain).accessibilityIdentifier("about-platform-" + platform.id)
            }
            Divider()
            Button { copyLink(content.repositoryURL) } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left.forwardslash.chevron.right").font(.system(size: 12))
                    Text(content.contributeLabel).font(.system(size: 12))
                    Image(systemName: "chevron.right").font(.system(size: 9))
                }.frame(maxWidth: .infinity, minHeight: 48).contentShape(Rectangle())
            }.buttonStyle(.plain).foregroundStyle(accent)
                .accessibilityIdentifier("about-contribute")
                .accessibilityLabel(content.contributeLabel + " · " + content.copyLinkLabel)
        }.padding(.horizontal, 12).aboutCard(outline: outline)
            .accessibilityElement(children: .contain).accessibilityIdentifier("about-platforms")
    }
    @ViewBuilder
    private func platformIcon(_ id: String) -> some View {
        switch id {
        case "weapp":
            if let icon = SourceIconCache.images["wechat"] {
                Image(decorative: icon, scale: 3).renderingMode(.template)
                    .resizable().scaledToFit().frame(width: 18, height: 18)
            }
        case "ios":
            Image(systemName: "iphone").resizable().scaledToFit().frame(width: 10.5, height: 16)
        case "ipad": Image(systemName: "ipad")
        case "android":
            Canvas { context, size in
                let scale = min(size.width, size.height) / 24
                context.scaleBy(x: scale, y: scale)
                // The full outline (including antennae) spans y=3...17.
                context.translateBy(x: 0, y: 2)
                var head = Path()
                head.addArc(center: CGPoint(x: 12, y: 13), radius: 9, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
                head.addLine(to: CGPoint(x: 21, y: 17)); head.addLine(to: CGPoint(x: 3, y: 17)); head.closeSubpath()
                context.stroke(head, with: .foreground, style: StrokeStyle(lineWidth: 1.3, lineCap: .round, lineJoin: .round))
                var antenna = Path()
                antenna.move(to: CGPoint(x: 5, y: 3)); antenna.addLine(to: CGPoint(x: 8, y: 7))
                antenna.move(to: CGPoint(x: 19, y: 3)); antenna.addLine(to: CGPoint(x: 16, y: 7))
                context.stroke(antenna, with: .foreground, style: StrokeStyle(lineWidth: 1.3, lineCap: .round))
                for x in [8.0, 16.0] {
                    context.fill(Path(ellipseIn: CGRect(x: x - 0.8, y: 11, width: 1.6, height: 1.6)), with: .foreground)
                }
            }.frame(width: 18, height: 18)
        case "harmony":
            VStack(spacing: 2) {
                Circle().strokeBorder(lineWidth: 1.2).frame(width: 13, height: 13)
                Capsule().frame(width: 12, height: 1.2)
            }
        case "macos": Image(systemName: "laptopcomputer")
        default: Image(systemName: "square.grid.2x2")
        }
    }
    private func platformStatus(_ platform: PadAboutContent.Platforms.Platform) -> some View {
        Text(platform.statusLabel).font(.system(size: 9, weight: .medium))
            .foregroundStyle(platformTint(platform.status)).lineLimit(1).fixedSize()
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(platformTint(platform.status).opacity(0.1), in: RoundedRectangle(cornerRadius: 4))
            .accessibilityIdentifier("about-platform-status-" + platform.id)
    }

    private func investment(_ investment: PadAboutContent.Investment, months: Int, contributors: PadAboutContent.Contributors) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(investment.title).font(.system(size: 15, weight: .semibold)).padding(.bottom, 11)
            Text(investment.engineeringTitle).font(.system(size: 12)).foregroundStyle(.secondary)
            let metrics = ForEach(investment.metrics) { metric in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(metric.value).font(.system(size: 24, weight: .semibold)).monospacedDigit()
                            .minimumScaleFactor(0.7).lineLimit(1)
                        Text(metric.label).font(.system(size: 11)).foregroundStyle(.secondary)
                            .lineLimit(1).minimumScaleFactor(0.75)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(11)
                        .background(inset, in: RoundedRectangle(cornerRadius: 8))
                        .accessibilityElement(children: .contain).accessibilityIdentifier("about-metric-" + metric.id)
            }
            if contributors.nodes.isEmpty {
                LazyVGrid(columns: columns, spacing: 7) { metrics }.padding(.vertical, 9)
            } else {
                HStack(alignment: .bottom, spacing: 8) {
                    metrics
                    Color.clear.frame(maxWidth: .infinity).frame(height: 0)
                }.overlay {
                    GeometryReader { geometry in
                        let side = max(0, (geometry.size.width - 16) / 3)
                        self.contributors(contributors, compact: true)
                            .frame(width: side, height: side)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    }
                }.padding(.vertical, 9)
            }
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
    private func contributors(_ content: PadAboutContent.Contributors, compact: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if !compact {
                Text(content.title).font(.system(size: 15, weight: .semibold)).padding(.bottom, 5)
                    .accessibilityIdentifier("about-contributors")
                note(content.note)
            }
            GeometryReader { geometry in
                let width = geometry.size.width
                ZStack(alignment: .topLeading) {
                    ForEach(content.nodes) { node in
                        let diameter = width * node.r * 2
                        let selected = about.selectedContributorID == node.id
                        Button {
                            if compact { about.contributorsExpanded = true }
                            else { about.selectedContributorID = node.id }
                        } label: {
                            ZStack {
                                Circle().fill(inset)
                                contributorMark(node, diameter: diameter, labeled: !compact && diameter > 105)
                                if !compact && diameter > 105 {
                                    Text(node.name).font(.system(size: 11)).lineLimit(1)
                                        .minimumScaleFactor(0.85)
                                        .frame(width: diameter * 0.88)
                                        .offset(y: diameter * 0.4)
                                }
                            }.frame(width: diameter, height: diameter).contentShape(Circle())
                                .overlay { if selected { Circle().strokeBorder(.secondary, lineWidth: 1.5) } }
                        }.buttonStyle(.plain).foregroundStyle(.primary)
                            .scaleEffect(about.hoveredContributorID == node.id ? 1.12 : 1)
                            .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: about.hoveredContributorID)
                            .onHover { about.hoveredContributorID = $0 ? node.id : nil }
                            .position(x: width * node.x, y: width * node.y)
                            .zIndex(selected || about.hoveredContributorID == node.id ? 1 : 0)
                            .accessibilityLabel(node.name + " · " + node.countLabel)
                            .accessibilityIdentifier("about-contributor-" + node.name)
                    }
                }
            }.aspectRatio(1, contentMode: .fit)
                .overlay(alignment: .bottomTrailing) {
                    if compact {
                        Button { about.contributorsExpanded = true } label: {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .font(.system(size: 11)).frame(width: 44, height: 44)
                        }.buttonStyle(.plain).foregroundStyle(.secondary)
                            .accessibilityLabel(content.expandLabel)
                            .accessibilityIdentifier("about-contributors-expand")
                    }
                }
            if !compact { HStack(spacing: 8) {
                Spacer(minLength: 0)
                if let selected = content.nodes.first(where: { $0.id == about.selectedContributorID }) {
                    Text(selected.name).font(.system(size: 12, weight: .medium))
                    Text(selected.countLabel).font(.system(size: 11)).foregroundStyle(.secondary)
                } else {
                    Text(content.hint).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }.frame(minHeight: 44).accessibilityElement(children: .contain)
                .accessibilityIdentifier("about-contributor-detail") }
        }
    }
    @ViewBuilder
    private func contributorMark(_ node: PadAboutContent.Contributors.Node, diameter: CGFloat, labeled: Bool) -> some View {
        if let image = AboutContributorImages.image(for: node.avatar) {
            let logo = Image(decorative: image, scale: 1).resizable().scaledToFit()
                .frame(width: diameter * 0.68, height: diameter * 0.68)
                .offset(y: labeled ? -diameter * 0.04 : 0)
            if dark && node.monochrome { logo.colorInvert() } else { logo }
        } else {
            Text(node.initial).font(.system(size: min(24, diameter * 0.45), weight: .medium))
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
