import SwiftUI
import CoreText
import LeaderboardKit
#if os(iOS)
import UIKit
import Photos
#else
import AppKit
#endif

@MainActor
private final class PadPresentationState: ObservableObject {
    @Published var licenseSection: PadLicenseSection?
    @Published var selectedLicenseSection: PadLicenseSection = .application
    @Published var note: String?
    @Published var savingScreenshot = false
    @Published var photoPermissionDenied = false
    @Published var showingQuotaTrackingHelp = false
    @Published var pairScrolled = false
}
private enum PadLicenseSection: String, Identifiable {
    case application, notices
    var id: String { rawValue }
}
// Keep scroll targets distinct from ForEach's zero-based integer identities.
private enum PadComparisonScrollTarget: Hashable {
    case top, rank(Int)
}
private struct PadRankingTop: PreferenceKey {
    static var defaultValue: CGFloat { 0 }
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
@MainActor
private struct PadRankingScrollTracking: ViewModifier {
    let onChange: (Bool) -> Void
    func body(content: Content) -> some View {
        if #available(iOS 18, macOS 15, *) {
            content.onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top > 32
            } action: { _, scrolled in onChange(scrolled) }
        } else {
            content.onPreferenceChange(PadRankingTop.self) { top in
                Task { @MainActor in onChange(top < -32) }
            }
        }
    }
}
@MainActor
private final class PadBoardDetail: ObservableObject {
    @Published var selectedCompany: CompanyStanding?
    @Published var showingSource = false
}

private enum PadNameTop: AlignmentID {
    static func defaultValue(in dimensions: ViewDimensions) -> CGFloat { dimensions[.top] }
}
private enum PadTitleInkTop: AlignmentID {
    static func defaultValue(in dimensions: ViewDimensions) -> CGFloat { dimensions[.top] }
}
private enum PadTitleInkBottom: AlignmentID {
    static func defaultValue(in dimensions: ViewDimensions) -> CGFloat { dimensions[.bottom] }
}
private extension VerticalAlignment {
    static let padNameTop = VerticalAlignment(PadNameTop.self)
    static let padTitleInkTop = VerticalAlignment(PadTitleInkTop.self)
    static let padTitleInkBottom = VerticalAlignment(PadTitleInkBottom.self)
}

// Place the subtitle beside the title's visible bottom, independent of font line boxes.
private struct PadBrandHeadingLayout: Layout {
    var compact = false
    private func measurements(_ subviews: Subviews, width: CGFloat? = nil) -> ([ViewDimensions], [CGPoint], CGSize) {
        var d = subviews.map { $0.dimensions(in: .unspecified) }
        if compact, let width { d[1] = subviews[1].dimensions(in: ProposedViewSize(width: max(1, width - d[0].width - 6), height: nil)) }
        let titleInkHeight = d[0][.padTitleInkBottom] - d[0][.padTitleInkTop]
        let x = d[0].width + 6
        var origins = [CGPoint(x: 0, y: -d[0][.padTitleInkTop]),
                       CGPoint(x: x, y: titleInkHeight - d[1][.padTitleInkBottom])]
        let top = origins.map(\.y).min() ?? 0
        for index in origins.indices { origins[index].y -= top }
        let height = zip(d, origins).map { $0.0.height + $0.1.y }.max() ?? 0
        return (d, origins, CGSize(width: x + d[1].width, height: height))
    }
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        measurements(subviews, width: proposal.width).2
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let (dimensions, origins, _) = measurements(subviews, width: bounds.width)
        for index in subviews.indices {
            subviews[index].place(at: CGPoint(x: bounds.minX + origins[index].x, y: bounds.minY + origins[index].y),
                                 anchor: .topLeading, proposal: ProposedViewSize(width: dimensions[index].width, height: dimensions[index].height))
        }
    }
    func explicitAlignment(of guide: VerticalAlignment, in bounds: CGRect, proposal: ProposedViewSize,
                           subviews: Subviews, cache: inout ()) -> CGFloat? {
        guard guide == .firstTextBaseline else { return nil }
        let (dimensions, origins, _) = measurements(subviews, width: bounds.width)
        return origins[0].y + dimensions[0][.firstTextBaseline]
    }
}

// Add the next row's actual name inset above the first row. That makes the
// header-to-name gap equal the gap between names, even when either wraps.
private struct PadBoardRowsLayout: Layout {
    private func measurements(_ proposal: ProposedViewSize, _ subviews: Subviews) -> ([ViewDimensions], CGFloat) {
        let dimensions = subviews.map { $0.dimensions(in: ProposedViewSize(width: proposal.width, height: nil)) }
        let inset = dimensions.isEmpty ? 0 : dimensions[min(1, dimensions.count - 1)][.padNameTop]
        return (dimensions, inset)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let (dimensions, inset) = measurements(proposal, subviews)
        return CGSize(width: dimensions.map(\.width).max() ?? 0,
                      height: inset + dimensions.reduce(0) { $0 + $1.height })
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let (dimensions, inset) = measurements(ProposedViewSize(width: bounds.width, height: nil), subviews)
        var y = bounds.minY + inset
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX, y: y), anchor: .topLeading,
                          proposal: ProposedViewSize(width: bounds.width, height: nil))
            y += dimensions[index].height
        }
    }
}

@MainActor
public struct LeaderboardPadView: View {
    @ObservedObject private var store: LeaderboardPadStore
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .caption) private var subtitleFontSize: CGFloat = 12
    @ScaledMetric(relativeTo: .body) private var englishTitleFontSize: CGFloat = 21
    @StateObject private var presentation = PadPresentationState()
    public static let repositoryURL = URL(string: "https://github.com/cloydlau/ai-benchgauge")!
    private let appStoreURL: URL?

    @StateObject private var cube = LeaderboardCubeState()
    public init(store: LeaderboardPadStore,
                appStoreID: String? = Bundle.main.object(forInfoDictionaryKey: "BenchGaugeAppStoreID") as? String) {
        self.store = store
        if let appStoreID, appStoreID.first.map({ "123456789".contains($0) }) == true,
           appStoreID.allSatisfy({ "0123456789".contains($0) }) {
            self.appStoreURL = URL(string: "https://apps.apple.com/app/id\(appStoreID)")
        } else { self.appStoreURL = nil }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--cube-preview") {
            _cube = StateObject(wrappedValue: LeaderboardCubeState(position: 0.5))
        } else if ProcessInfo.processInfo.arguments.contains("--ui-testing") && ProcessInfo.processInfo.arguments.contains("--arena-preview") {
            let preview = LeaderboardCubeState(position: 1)
            preview.face = 1
            _cube = StateObject(wrappedValue: preview)
        }
        #endif
    }
    private var usesReducedMotion: Bool {
        #if DEBUG
        reduceMotion || ProcessInfo.processInfo.arguments.contains("--reduce-motion")
        #else
        reduceMotion
        #endif
    }
    private func usesCube(width: CGFloat) -> Bool {
        #if os(iOS)
        UIDevice.current.userInterfaceIdiom == .phone || width < 760
        #else
        width < 760
        #endif
    }
    private var isPhone: Bool {
        #if os(iOS)
        UIDevice.current.userInterfaceIdiom == .phone
        #else
        false
        #endif
    }
    private func tr(_ en: String, _ zh: String) -> String { store.language.text(en, zh) }

    public var body: some View {
        GeometryReader { geometry in
            if usesCube(width: geometry.size.width) {
                VStack(alignment: .leading, spacing: 12) {
                    compactHeader
                    compactControls(width: geometry.size.width - 24)
                    cubeBoards(bottomInset: geometry.safeAreaInsets.bottom)
                }
                .padding(.horizontal, 12).padding(.top, 8)
                .ignoresSafeArea(.container, edges: .bottom)
            } else {
                pairedBoards(bottomInset: geometry.safeAreaInsets.bottom)
            }
        }
        .background { Color.padBackground.ignoresSafeArea() }
        .overlay(alignment: .bottom) {
            if let note = presentation.note {
                Text(note).font(.footnote).padding(12)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8)).padding(20)
            }
        }
        .sheet(item: $presentation.licenseSection) { licenseSheet($0) }
        .alert(AppFeatureCopy.quotaTitle(language: store.language), isPresented: $presentation.showingQuotaTrackingHelp) {
            Button(tr("Got it", "知道了"), role: .cancel) { }
        } message: {
            Text(AppFeatureCopy.quotaMessage(language: store.language))
        }
        #if os(iOS)
        .alert(tr("Cannot save to Photos", "无法保存到相册"), isPresented: $presentation.photoPermissionDenied) {
            Button(tr("Open Settings", "打开设置")) {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }
            Button(tr("Cancel", "取消"), role: .cancel) { }
        } message: {
            Text(tr("Allow adding photos in Settings to save leaderboard images.", "请在系统设置中允许添加照片，以保存榜单图片。"))
        }
        #endif
        .task(id: store.category) { await store.refresh() }
        #if DEBUG && os(iOS)
        .task { await writeDebugExportIfRequested() }
        #endif
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await store.refresh() } }
            else {
                cancelCubeEntrance()
                if cube.dragging { turnCube(to: cube.face) }
            }
        }
        .onChange(of: usesReducedMotion) { cancelCubeEntrance() }
        .onChange(of: store.category) { resetComparison() }
        .onChange(of: store.grouping) { resetComparison() }
        .environment(\.locale, store.language.locale)
        .preferredColorScheme(store.appearance == "dark" ? .dark : store.appearance == "light" ? .light : nil)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            brandHeading
            Spacer(minLength: 4)
            updateButton
        }
    }
    private var updateButton: some View {
            TimelineView(.periodic(from: .now, by: 60)) { context in
                Button { Task { await store.refresh(force: true) } } label: {
                    HStack(spacing: 8) {
                        Text(tr("UPDATED", "更新时间")).fontWeight(.semibold).foregroundStyle(.secondary)
                        Text(LeaderboardPresentation.rankingUpdated(store.snapshot, category: store.category,
                            language: store.language, now: context.date))
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .foregroundStyle(Color.secondary)
                            .background(Color.secondary.opacity(0.10), in: Capsule())
                    }.font(.caption).monospacedDigit().foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .disabled(store.category.boardKinds.contains { store.refreshing.contains($0) })
                .accessibilityLabel(tr("Click to refresh boards", "点击刷新榜单"))
                .accessibilityIdentifier("refresh")
            }
    }
    @ViewBuilder private var compactHeader: some View {
        if isPhone { phoneHeader }
        else { existingCompactHeader }
    }
    private var existingCompactHeader: some View {
        ViewThatFits(in: .horizontal) {
            header.fixedSize(horizontal: true, vertical: false)
            VStack(alignment: .leading, spacing: 4) {
                brandHeading
                updateButton
            }
        }
    }
    private var phoneHeader: some View {
        GeometryReader { geometry in
            let groupingWidth: CGFloat = store.language == .english ? 160 : 92
            HStack(spacing: 4) {
                brandHeading(titleFontSize: store.language == .english ? 14 : 17)
                    .frame(width: max(1, geometry.size.width - groupingWidth - 4), alignment: .leading)
                phoneGrouping.frame(width: groupingWidth)
            }
        }.frame(height: 44)
    }
    @ViewBuilder private var phoneGrouping: some View {
        #if os(iOS)
        let segmentWidth: CGFloat = store.language == .english ? 80 : 46
        PadSegmentedControl(values: LeaderboardGrouping.allCases,
            titles: [tr("Models", "模型"), tr("Companies", "公司")], selection: $store.grouping,
            identifier: "grouping", label: tr("Grouping", "分组"), segmentWidth: segmentWidth, fontSize: 12)
            .frame(width: segmentWidth * 2, height: 32).id(segmentWidth)
        #endif
    }
    @ViewBuilder private var brandHeading: some View {
        if store.language == .english && englishTitleFontSize > 21 {
            ViewThatFits(in: .horizontal) {
                brandHeading(titleFontSize: englishTitleFontSize)
                brandHeading(titleFontSize: max(21, englishTitleFontSize * 0.75))
                brandHeading(titleFontSize: 21)
            }
        } else {
            brandHeading(titleFontSize: englishTitleFontSize)
        }
    }
    private func brandHeading(titleFontSize: CGFloat) -> some View {
        let subtitleSize = headingSubtitleFontSize(titleFontSize: titleFontSize)
        let subtitle = AppFeatureCopy.subtitle(language: store.language)
        let subtitleInk = Self.textInkBounds(subtitle, font: Self.subtitleFont(subtitleSize))
        let english = store.language == .english
        let title = store.language.appName
        return PadBrandHeadingLayout(compact: isPhone) {
            appTitle(fontSize: titleFontSize)
                .alignmentGuide(.padTitleInkTop) { dimensions in
                    english
                        ? Self.textInkTop(dimensions, text: title,
                            font: CTFontCreateWithName("SnellRoundhand-Bold" as CFString, titleFontSize, nil))
                        : dimensions.height - dimensions[.bottom]
                }
                .alignmentGuide(.padTitleInkBottom) { $0[.bottom] }
                .accessibilityIdentifier("brand-title")
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                FeatureSubtitle(language: store.language).lineLimit(isPhone ? 2 : 1).accessibilityIdentifier("brand-subtitle")
                Image(systemName: "questionmark.circle")
                    .resizable().scaledToFit()
                    .frame(width: subtitleInk.height, height: subtitleInk.height)
                    .opacity(0.55)
                    .alignmentGuide(.firstTextBaseline) { $0.height + subtitleInk.minY }
                    .accessibilityHidden(true)
            }
            .font(.system(size: subtitleSize, weight: .semibold)).foregroundStyle(.secondary)
            .overlay {
                GeometryReader { geometry in
                    Color.clear.contentShape(Rectangle())
                        .onTapGesture { location in
                            // SwiftUI also recognizes nearby taps; accept only the visible label's bounds.
                            guard CGRect(origin: .zero, size: geometry.size).contains(location) else { return }
                            presentation.showingQuotaTrackingHelp = true
                        }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { presentation.showingQuotaTrackingHelp = true }
            .accessibilityIdentifier("quota-tracking-help")
            .accessibilityLabel(subtitle)
            .accessibilityHint(AppFeatureCopy.quotaHelpLabel(language: store.language))
            .padding(.vertical, 4)
            .alignmentGuide(.padTitleInkBottom) { dimensions in
                Self.textInkBottom(dimensions, text: subtitle, font: Self.subtitleFont(subtitleSize))
            }
        }
    }
    private func headingSubtitleFontSize(titleFontSize: CGFloat) -> CGFloat {
        let titleHeight: CGFloat
        if store.language == .english {
            titleHeight = Self.textInkBounds(store.language.appName,
                font: CTFontCreateWithName("SnellRoundhand-Bold" as CFString, titleFontSize, nil)).height
        } else {
            // ChineseBrandTitle centers every glyph on the same visible axis.
            let latin = CTFontCreateUIFontForLanguage(.system, 21, nil)!
            let chinese = CTFontCreateWithName(BrandFont.chineseName as CFString, 25, nil)
            titleHeight = max(Self.textInkBounds("AI", font: latin).height, Self.textInkBounds("天梯", font: chinese).height)
        }
        let captionHeight = Self.textInkBounds(AppFeatureCopy.subtitle(language: store.language), font: Self.subtitleFont(subtitleFontSize)).height
        let scale = min(1, titleHeight / max(1, captionHeight))
        return (isPhone ? (store.language == .english ? 8 : 10) : subtitleFontSize) * scale
    }
    nonisolated private static func subtitleFont(_ size: CGFloat) -> CTFont {
        let base = CTFontCreateUIFontForLanguage(.system, size, nil)!
        let descriptor = CTFontDescriptorCreateWithAttributes([
            kCTFontTraitsAttribute: [kCTFontWeightTrait: 0.3]
        ] as CFDictionary)
        return CTFontCreateCopyWithAttributes(base, size, nil, descriptor)
    }
    private var appTitle: some View { appTitle(fontSize: englishTitleFontSize) }
    @ViewBuilder private func appTitle(fontSize: CGFloat) -> some View {
        let title = store.language.appName
        if store.language == .english {
            EnglishBrandTitle(fontSize: fontSize)
                .alignmentGuide(.bottom) { dimensions in
                    Self.textInkBottom(dimensions, text: title,
                        font: CTFontCreateWithName("SnellRoundhand-Bold" as CFString, fontSize, nil))
                }
        } else {
            ChineseBrandTitle()
        }
    }
    nonisolated private static func textInkBounds(_ text: String, font: CTFont) -> CGRect {
        let attributed = NSAttributedString(string: text,
            attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font])
        return CTLineGetBoundsWithOptions(CTLineCreateWithAttributedString(attributed), .useGlyphPathBounds)
    }
    nonisolated private static func textInkTop(_ dimensions: ViewDimensions, text: String, font: CTFont) -> CGFloat {
        let ink = textInkBounds(text, font: font)
        guard !ink.isNull, !ink.isEmpty else { return dimensions[.top] }
        return dimensions[.firstTextBaseline] - ink.maxY
    }
    nonisolated private static func textInkBottom(_ dimensions: ViewDimensions, text: String, font: CTFont) -> CGFloat {
        let ink = textInkBounds(text, font: font)
        guard !ink.isNull, !ink.isEmpty else { return dimensions[.bottom] }
        return dimensions[.firstTextBaseline] - ink.minY
    }

    private var controls: some View { tabletControls(categoryWidth: 360) }

    // Keep the category centered independently of the leading grouping control.
    // The minimum width leaves room for grouping and an equal trailing margin;
    // narrower iPad windows put the centered category on its own row instead.
    private func tabletControls(categoryWidth: CGFloat) -> some View {
        ViewThatFits(in: .horizontal) {
            ZStack {
                HStack { groupingPicker.frame(width: 180); Spacer(minLength: 0) }
                categoryControl(segmentWidth: categoryWidth / 4).frame(width: categoryWidth)
            }.frame(minWidth: categoryWidth + 376, maxWidth: .infinity)
            VStack(alignment: .leading, spacing: 8) {
                groupingPicker.frame(width: 180)
                categoryControl(segmentWidth: categoryWidth / 4).frame(width: categoryWidth)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }
    @ViewBuilder private func compactControls(width: CGFloat) -> some View {
        if isPhone {
            categoryControl(segmentWidth: width / 4).frame(width: width)
        } else {
            tabletControls(categoryWidth: min(360, width))
        }
    }
    @ViewBuilder private func categoryControl(segmentWidth: CGFloat) -> some View {
        #if os(iOS)
        PadSegmentedControl(values: LeaderboardCategory.allCases,
            titles: LeaderboardCategory.allCases.map { LeaderboardPresentation.title($0, language: store.language) },
            selection: $store.category, identifier: "category", label: tr("Leaderboard category", "榜单类别"), segmentWidth: segmentWidth)
            .frame(height: 32).id(segmentWidth)
        #else
        categoryPicker
        #endif
    }
    private var categoryPicker: some View {
        #if os(iOS)
        PadSegmentedControl(values: LeaderboardCategory.allCases,
            titles: LeaderboardCategory.allCases.map { LeaderboardPresentation.title($0, language: store.language) },
            selection: $store.category, identifier: "category", label: tr("Leaderboard category", "榜单类别"))
            .frame(height: 32)
        #else
        Picker(tr("Leaderboard category", "榜单类别"), selection: $store.category) {
            ForEach(LeaderboardCategory.allCases) { category in
                Text(LeaderboardPresentation.title(category, language: store.language)).tag(category)
            }
        }.pickerStyle(.segmented).accessibilityIdentifier("category")
        #endif
    }
    private var groupingPicker: some View {
        #if os(iOS)
        PadSegmentedControl(values: LeaderboardGrouping.allCases,
            titles: [tr("Models", "模型"), tr("Companies", "公司")], selection: $store.grouping,
            identifier: "grouping", label: tr("Grouping", "分组")).frame(height: 32)
        #else
        Picker(tr("Grouping", "分组"), selection: $store.grouping) {
            Text(tr("Models", "模型")).tag(LeaderboardGrouping.model)
            Text(tr("Companies", "公司")).tag(LeaderboardGrouping.company)
        }.pickerStyle(.segmented).accessibilityIdentifier("grouping")
        #endif
    }

    private var cubeSelector: some View {
        HStack(spacing: 6) {
            ForEach(Array(store.category.boardKinds.enumerated()), id: \.offset) { index, kind in
                Button { turnCube(to: index) } label: {
                    Text(kind.sourcePrefix == "Arena" ? tr("User votes", "用户盲测") : tr("Task benchmarks", "任务测评"))
                        .font(.caption.weight(.semibold))
                        .lineLimit(2).frame(maxWidth: .infinity, minHeight: 38)
                        .foregroundStyle(cube.face == index ? Color.accentColor : Color.secondary)
                        .background(cube.face == index ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.06),
                                    in: RoundedRectangle(cornerRadius: 8))
                }.buttonStyle(.plain).accessibilityIdentifier("face-\(index)")
                    .accessibilityAddTraits(cube.face == index ? .isSelected : [])
            }
        }
    }
    private func resetComparison() {
        cancelCubeEntrance()
        cube.rank = nil
        cube.generation += 1
        if cube.dragging { turnCube(to: cube.face) }
    }
    private func turnCube(to face: Int) {
        cancelCubeEntrance()
        cube.dragging = false
        cube.turnSerial += 1
        let serial = cube.turnSerial
        cube.turning = true
        cube.face = face
        withAnimation(.easeInOut(duration: usesReducedMotion ? 0.18 : 0.42)) {
            cube.position = Double(face)
        } completion: {
            if cube.turnSerial == serial { cube.turning = false }
        }
    }
    private var cubeContentReady: Bool {
        store.category.boardKinds.allSatisfy { !(store.snapshot.boards[$0]?.entries.isEmpty ?? true) }
    }
    private func cancelCubeEntrance() {
        // Do not touch an ordinary drag/turn after the introduction has ended.
        guard !cube.entrancePlayed || cube.entranceActive || cube.entranceHintVisible else { return }
        var transaction = Transaction(); transaction.disablesAnimations = true
        withTransaction(transaction) { cube.finishEntrance() }
    }
    private func playCubeEntrance() async {
        guard isPhone, cubeContentReady, scenePhase == .active else { return }
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--cube-entrance-preview") {
            guard cube.beginEntrance(reduceMotion: usesReducedMotion) != nil else { return }
            cube.entranceProgress = 1
            if !usesReducedMotion { cube.position = 0.28 }
            return
        }
        guard !arguments.contains("--cube-preview"), !arguments.contains("--arena-preview"),
              !arguments.contains("--ui-testing") || arguments.contains("--cube-entrance") else { return }
        #endif
        do {
            try await Task.sleep(for: .milliseconds(220))
            try Task.checkCancellation()
            guard let serial = cube.beginEntrance(reduceMotion: usesReducedMotion) else { return }
            withAnimation(.smooth(duration: 0.42)) {
                cube.entranceProgress = 1
                if !usesReducedMotion { cube.position = 0.28 }
            }
            try await Task.sleep(for: .milliseconds(550))
            guard cube.isCurrentEntrance(serial) else { return }
            withAnimation(.spring(duration: 0.7, bounce: 0.08)) { cube.position = Double(cube.face) }
            try await Task.sleep(for: .milliseconds(750))
            guard cube.isCurrentEntrance(serial) else { return }
            cube.settleEntrance(serial)
            try await Task.sleep(for: .milliseconds(1600))
            guard cube.isCurrentEntrance(serial) else { return }
            // Invalidate the timer as the hint starts fading, so no delayed
            // completion can snap a gesture that starts during that fade.
            withAnimation(.easeOut(duration: 0.3)) { cube.finishEntrance(serial) }
        } catch {
            cancelCubeEntrance()
        }
    }
    private var cubeEntranceHint: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                Label(tr("Scroll", "上下滚动"), systemImage: "arrow.up.arrow.down")
                Rectangle().fill(.secondary.opacity(0.25)).frame(width: 1, height: 12)
                Label(tr("Switch boards", "左右切换"), systemImage: "arrow.left.arrow.right")
            }.fixedSize()
            VStack(spacing: 6) {
                Label(tr("Scroll", "上下滚动"), systemImage: "arrow.up.arrow.down")
                Label(tr("Switch boards", "左右切换"), systemImage: "arrow.left.arrow.right")
            }.fixedSize()
        }
        .font(.caption2.weight(.medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14).padding(.vertical, 9)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.secondary.opacity(0.12), lineWidth: 0.5))
        .padding(.bottom, 14)
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("cube-launch-hint")
    }
    private func cubeBoards(bottomInset: CGFloat) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                ForEach(Array(store.category.boardKinds.enumerated()), id: \.element) { index, kind in
                    cubeFace(kind, index: index, size: geometry.size, bottomInset: bottomInset)
                }
            }
            .id(cube.generation)
            .opacity(0.65 + cube.entranceProgress * 0.35)
            .scaleEffect(usesReducedMotion ? 1 : 0.985 + cube.entranceProgress * 0.015)
            .offset(y: usesReducedMotion ? 0 : (1 - cube.entranceProgress) * 12)
            .clipped()
            .overlay(alignment: .bottom) {
                if cube.entranceHintVisible {
                    cubeEntranceHint.opacity(cube.entranceProgress).transition(.opacity)
                }
            }
            .task(id: cubeContentReady && scenePhase == .active) { await playCubeEntrance() }
            .onDisappear { cancelCubeEntrance() }
            .onChange(of: geometry.size) { if cube.dragging { turnCube(to: cube.face) } }
            .contentShape(Rectangle())
            .simultaneousGesture(DragGesture(minimumDistance: 16)
                .onChanged { value in
                    cancelCubeEntrance()
                    guard !cube.turning else { return }
                    guard cube.dragging || LeaderboardCube.isHorizontal(x: value.translation.width, y: value.translation.height) else { return }
                    cube.dragging = true
                    if !usesReducedMotion {
                        cube.position = LeaderboardCube.position(face: cube.face, translation: value.translation.width, width: geometry.size.width)
                    }
                }
                .onEnded { value in
                    guard cube.dragging else { return }
                    turnCube(to: LeaderboardCube.destination(face: cube.face, translation: value.translation.width,
                                                             predicted: value.predictedEndTranslation.width, width: geometry.size.width))
                })
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("cube-viewport")
            .accessibilityLabel(LeaderboardPresentation.title(store.category, language: store.language))
            .accessibilityValue(store.category.boardKinds[cube.face].sourceLinkTitle)
            .accessibilityHint(tr("Scroll vertically to explore; switch boards horizontally.", "上下滚动查看，左右切换榜单。"))
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: turnCube(to: 1)
                case .decrement: turnCube(to: 0)
                @unknown default: break
                }
            }
        }
    }
    private func rankingBackToTop(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "arrow.up.to.line")
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 44, height: 44)
                .background(.regularMaterial, in: Circle())
                .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tr("Back to top", "返回顶部"))
        .accessibilityIdentifier("leaderboard-back-to-top")
    }

    private func pairedBoards(bottomInset: CGFloat) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    header.id(PadComparisonScrollTarget.top)
                        .background {
                            GeometryReader { geometry in
                                Color.clear.preference(key: PadRankingTop.self,
                                    value: geometry.frame(in: .named("paired-rankings")).minY)
                            }
                        }
                    controls
                    boardPair(wide: true)
                    footer
                }
                .padding(18)
                .padding(.bottom, bottomInset)
                .frame(maxWidth: 1100)
                .frame(maxWidth: .infinity)
            }
            .coordinateSpace(name: "paired-rankings")
            .modifier(PadRankingScrollTracking { presentation.pairScrolled = $0 })
            .modifier(PadLeaderboardScrollEdges(edges: .bottom))
            .ignoresSafeArea(.container, edges: .bottom)
            .refreshable { await store.refresh(force: true) }
            .overlay(alignment: .bottomTrailing) {
                if presentation.pairScrolled {
                    rankingBackToTop {
                        withAnimation(usesReducedMotion ? nil : .easeOut(duration: 0.25)) {
                            proxy.scrollTo(PadComparisonScrollTarget.top, anchor: .top)
                        }
                    }.padding(.trailing, 20).padding(.bottom, bottomInset + 64)
                }
            }
        }
    }

    private func cubeFace(_ kind: LeaderboardKind, index: Int, size: CGSize, bottomInset: CGFloat) -> some View {
        let generation = cube.generation
        return ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    cubeSelector.id(PadComparisonScrollTarget.top)
                    boardCard(kind, compact: true)
                        .background {
                            GeometryReader { geometry in
                                let frame = geometry.frame(in: .named("rank-scroll-\(kind.rawValue)"))
                                Color.clear.preference(key: LeaderboardRankFrames.self,
                                    value: [0: LeaderboardRankFrame(minY: frame.minY, maxY: frame.maxY)])
                            }
                        }
                    compactFooter
                }
                .padding(.bottom, bottomInset + 8)
            }
                .modifier(PadLeaderboardScrollEdges())
                .coordinateSpace(name: "rank-scroll-\(kind.rawValue)")
                .onPreferenceChange(LeaderboardRankFrames.self) { frames in
                    Task { @MainActor in
                        guard generation == cube.generation, index == cube.face,
                              !cube.dragging && !cube.turning && !cube.entranceActive else { return }
                        // Zero identifies the full card's top, including its
                        // source and column headers. Only align a ranking row
                        // once the user has actually scrolled past that top.
                        let rank = (frames[0]?.minY ?? -.infinity) >= -1 ? 0
                            : LeaderboardCube.visibleRank(frames.filter { $0.key > 0 }, height: size.height)
                        if cube.rank != rank { cube.rank = rank }
                    }
                }
                .onChange(of: cube.face) { _, face in
                    if face == index, let rank = cube.rank {
                        // Move the incoming source to the same ranking position
                        // before rotating it into view; never animate the scroll.
                        var transaction = Transaction(); transaction.disablesAnimations = true
                        let target: PadComparisonScrollTarget = rank == 0 ? .top : .rank(rank)
                        withTransaction(transaction) { proxy.scrollTo(target, anchor: .top) }
                    }
                }
                .refreshable { await store.refresh(force: true) }
                .frame(width: size.width, height: size.height)
                .overlay(alignment: .bottomTrailing) {
                    if index == cube.face && (cube.rank ?? 0) > 1 {
                        rankingBackToTop {
                            withAnimation(usesReducedMotion ? nil : .easeOut(duration: 0.25)) {
                                proxy.scrollTo(PadComparisonScrollTarget.top, anchor: .top)
                            }
                        }.padding(.trailing, 12).padding(.bottom, bottomInset + 64)
                    }
                }
                .background(Color.padBackground)
                .modifier(CubeFace(position: cube.position, face: index, width: size.width, reduceMotion: usesReducedMotion))
                .allowsHitTesting(index == cube.face && !cube.dragging && !cube.turning)
                .accessibilityHidden(index != cube.face || cube.dragging)
        }
    }
    private var compactFooter: some View {
        HStack(spacing: 12) {
            if !isPhone {
            Link(destination: Self.repositoryURL) {
                if let image = PadOrganizationLogo.image(for: "github") {
                    image.renderingMode(.template).resizable().scaledToFit().frame(width: 16, height: 16)
                } else { Image(systemName: "link") }
            }.accessibilityLabel("GitHub").frame(minHeight: 44)
            #if os(iOS)
            PhoneMenuButton(title: "Cloyd Lau · MIT", identifier: "attribution", items: [
                PhoneMenuItem(title: "MIT License", identifier: "license", action: { openLicense(.application) }),
                PhoneMenuItem(title: tr("Open-source notices", "开源声明"), identifier: "open-source-notices", action: { openLicense(.notices) }),
            ], sourceTitle: tr("Sources", "数据来源"), sources: store.category.boardKinds.map { kind in
                PhoneMenuItem(title: kind.sourceLinkTitle, identifier: "source-link-\(kind.rawValue)", action: { UIApplication.shared.open(kind.sourceURL) })
            }).frame(width: 110, height: 44)
            #else
            Menu {
                Button("MIT License") { openLicense(.application) }.accessibilityIdentifier("license")
                Button(tr("Open-source notices", "开源声明")) { openLicense(.notices) }.accessibilityIdentifier("open-source-notices")
                Section(tr("Sources", "数据来源")) {
                    ForEach(store.category.boardKinds, id: \.self) { kind in Link(kind.sourceLinkTitle, destination: kind.sourceURL) }
                }
            } label: {
                Text("Cloyd Lau · MIT").font(.caption).frame(minHeight: 44).contentShape(Rectangle())
            }.accessibilityIdentifier("attribution")
            #endif
            }
            Spacer(minLength: 0)
            if isPhone {
                Menu {
                    ForEach(store.category.boardKinds, id: \.self) { kind in Link(kind.sourceLinkTitle, destination: kind.sourceURL) }
                } label: { Image(systemName: "link") }
                .accessibilityLabel(tr("Sources", "数据来源")).accessibilityIdentifier("source-menu")
            }
            screenshotButton(compact: true).frame(width: 44, height: 44)
            #if os(iOS)
            PhoneMenuButton(title: languageLabel(store.language), identifier: "language-menu",
                items: AppLanguage.allCases.map { language in
                    PhoneMenuItem(title: languageLabel(language), identifier: "language-\(language.rawValue)",
                        action: { store.language = language }, selected: language == store.language)
                }, label: tr("Language", "语言")).frame(width: 44, height: 44)
            #else
            Menu {
                ForEach(AppLanguage.allCases, id: \.self) { language in
                    Button { store.language = language } label: {
                        if language == store.language { Label(languageLabel(language), systemImage: "checkmark") }
                        else { Text(languageLabel(language)) }
                    }
                }
            } label: { Text(languageLabel(store.language)).font(.caption).frame(minWidth: 40, minHeight: 44).contentShape(Rectangle()) }
                .accessibilityLabel(tr("Language", "语言")).accessibilityIdentifier("language-menu")
            #endif
            if isPhone {
                Menu {
                    Button(tr("System", "跟随系统")) { store.appearance = "system" }
                    Button(tr("Light", "浅色")) { store.appearance = "light" }
                    Button(tr("Dark", "深色")) { store.appearance = "dark" }
                } label: { Image(systemName: "circle.lefthalf.filled").frame(width: 44, height: 44) }
                .accessibilityLabel(tr("Appearance", "外观")).accessibilityIdentifier("appearance-menu")
            }
        }.buttonStyle(.plain).foregroundStyle(.secondary).lineLimit(1)
    }
    private func languageLabel(_ language: AppLanguage) -> String {
        switch language { case .english: "EN"; case .chinese: "简中"; case .traditionalChinese: "繁中" }
    }

    @ViewBuilder private func boardPair(wide: Bool, isImage: Bool = false, exportScheme: ColorScheme? = nil) -> some View {
        if wide {
            HStack(alignment: .top, spacing: 12) {
                ForEach(store.category.boardKinds, id: \.self) { kind in boardCard(kind, isImage: isImage, exportScheme: exportScheme) }
            }
        } else {
            VStack(spacing: 12) {
                ForEach(store.category.boardKinds, id: \.self) { kind in boardCard(kind, isImage: isImage, exportScheme: exportScheme) }
            }
        }
    }
    private func boardCard(_ kind: LeaderboardKind, isImage: Bool = false, compact: Bool = false, exportScheme: ColorScheme? = nil) -> some View {
        PadBoardCard(kind: kind, board: store.snapshot.boards[kind], rowPresentation: store.rowPresentation(for: kind), grouping: store.grouping,
            language: store.language, filter: store.countryFilter(for: kind), opennessFilter: store.opennessFilter(for: kind),
            isRefreshing: store.refreshing.contains(kind), isImage: isImage, compact: compact, exportScheme: exportScheme,
            refresh: { Task { await store.refresh(force: true) } },
            selectCountry: { store.setCountryFilter($0, for: kind); resetComparison() },
            selectOpenness: { store.setOpennessFilter($0, for: kind); resetComparison() }, copyName: { name in
                cancelCubeEntrance()
                // A simultaneous cube drag can also release a name button.
                // Only a tap on a settled, stationary board may copy a name.
                guard !compact || (!cube.dragging && !cube.turning) else { return }
                copyName(name)
            })
    }

    private var footer: some View {
        ViewThatFits(in: .horizontal) {
            footerRow(compact: false, showsSources: true)
            footerRow(compact: false, showsSources: false)
            footerRow(compact: true, showsSources: false)
        }.font(.caption).foregroundStyle(.secondary).lineLimit(1)
    }
    private func footerRow(compact: Bool, showsSources: Bool) -> some View {
        HStack(spacing: 7) {
            HStack(spacing: 7) {
                Link(destination: Self.repositoryURL) {
                    if let image = PadOrganizationLogo.image(for: "github") {
                        image.renderingMode(.template).resizable().scaledToFit().frame(width: 13, height: 13)
                    } else { Image(systemName: "link") }
                }.accessibilityLabel("GitHub")
                Text("Cloyd Lau")
                Text("·")
                Button(compact ? "MIT" : "MIT License") { openLicense(.application) }.accessibilityIdentifier("license")
                Text("·")
                Button(tr(compact ? "Notices" : "Open-source notices", "开源声明")) { openLicense(.notices) }
                    .accessibilityIdentifier("open-source-notices")
            }.fixedSize()
            Spacer(minLength: 8)
            HStack(spacing: 7) {
                if showsSources {
                    Text(tr("Sources", "数据来源"))
                    Link(store.category.boardKinds[0].sourceLinkTitle, destination: store.category.boardKinds[0].sourceURL)
                    Text("·")
                    Link(store.category.boardKinds[1].sourceLinkTitle, destination: store.category.boardKinds[1].sourceURL)
                } else {
                    Menu(tr("Sources", "数据来源")) {
                        ForEach(store.category.boardKinds, id: \.self) { kind in Link(kind.sourceLinkTitle, destination: kind.sourceURL) }
                    }
                }
                Text("·")
                screenshotButton(compact: compact)
                Text("·")
                Picker(tr("Language", "语言"), selection: $store.language) {
                    Text("EN").tag(AppLanguage.english)
                    Text("简中").tag(AppLanguage.chinese)
                    Text("繁中").tag(AppLanguage.traditionalChinese)
                }.pickerStyle(.segmented).frame(width: 150).accessibilityIdentifier("language")
            }.fixedSize(horizontal: true, vertical: false)
        }.buttonStyle(.plain)
    }

    @ViewBuilder private func screenshotButton(compact: Bool) -> some View {
        #if os(iOS)
        Menu {
            Button { copyScreenshot() } label: {
                Label(tr("Copy image", "复制图片"), systemImage: "doc.on.doc")
            }.accessibilityIdentifier("copy-screenshot")
            Button { Task { await saveScreenshotToPhotos() } } label: {
                Label(tr("Save to Photos", "保存到相册"), systemImage: "square.and.arrow.down")
            }.accessibilityIdentifier("save-screenshot")
        } label: { screenshotLabel(compact: compact) }
        .disabled(presentation.savingScreenshot)
        .accessibilityLabel(tr("Screenshot", "截图")).accessibilityIdentifier("share")
        #else
        Button { copyScreenshot() } label: { screenshotLabel(compact: compact) }
            .accessibilityLabel(tr("Screenshot", "截图")).accessibilityIdentifier("share")
        #endif
    }
    @ViewBuilder private func screenshotLabel(compact: Bool) -> some View {
        if compact { Image(systemName: "camera") }
        else { Label(tr("Screenshot", "截图"), systemImage: "camera") }
    }

    private func openLicense(_ section: PadLicenseSection) {
        presentation.selectedLicenseSection = section
        presentation.licenseSection = section
    }
    private func licenseSheet(_ section: PadLicenseSection) -> some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker(tr("License section", "许可证分类"), selection: $presentation.selectedLicenseSection) {
                    Text(tr("Application license", "本软件许可")).tag(PadLicenseSection.application)
                    Text(tr("Open-source notices", "开源软件声明")).tag(PadLicenseSection.notices)
                }.pickerStyle(.segmented).padding(20).accessibilityIdentifier("license-section")
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if presentation.selectedLicenseSection == .application {
                            HStack {
                                Text("AI BenchGauge").font(.headline)
                                Spacer()
                                Text("MIT").font(.caption.weight(.medium)).padding(.horizontal, 8).padding(.vertical, 3)
                                    .background(.quaternary, in: Capsule())
                            }
                            Text(tr("Application license", "本软件的许可证")).foregroundStyle(.secondary)
                            Link(tr("Project source", "项目源码"), destination: Self.repositoryURL)
                            Text(Self.license).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                        } else {
                            Text("Slide Xiaxing 1.000 · SIL OFL 1.1").font(.headline)
                            Text(tr("Calligraphy for the Chinese brand title; the subset is renamed BenchGauge Calligraphy.", "中文品牌标题的书法字体；子集更名为 BenchGauge Calligraphy。"))
                                .foregroundStyle(.secondary)
                            Link(tr("Font source", "字体来源"), destination: URL(string: "https://github.com/maoken-fonts/slidefont")!)
                            Text(BrandFont.licenseText).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                        }
                    }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .navigationTitle(tr("Licenses & notices", "许可证与声明"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(tr("Done", "完成")) { presentation.licenseSection = nil } } }
        }
    }
    private static var license: String {
        guard let url = Bundle.module.url(forResource: "AI-BenchGauge", withExtension: "txt") else { return "MIT License" }
        return (try? String(contentsOf: url, encoding: .utf8)) ?? "MIT License"
    }

    func renderLeaderboardImage(width: CGFloat = 1000, scheme: ColorScheme = .light) -> CGImage? {
        let secondary = scheme == .dark ? Color(red: 0.6, green: 0.6, blue: 0.6) : Color(red: 0.5, green: 0.5, blue: 0.5)
        let content = VStack(alignment: .leading, spacing: 12) {
            HStack {
                appTitle
                Text(tr(store.grouping == .model ? "Models" : "Companies", store.grouping == .model ? "模型" : "公司"))
                Text(LeaderboardPresentation.title(store.category, language: store.language))
                Spacer()
                Text(tr("UPDATED", "更新时间") + " " + LeaderboardPresentation.rankingUpdated(store.snapshot,
                    category: store.category, language: store.language)).font(.caption).foregroundStyle(secondary)
            }
            boardPair(wide: width >= 760, isImage: true, exportScheme: scheme)
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .bottom) {
                    screenshotDownloadCredit.fixedSize(horizontal: true, vertical: false)
                    Spacer(minLength: 16)
                    if !isPhone { Text("Cloyd Lau · MIT License").fixedSize() }
                }
                VStack(alignment: .leading, spacing: 6) {
                    screenshotDownloadCredit
                    if !isPhone { Text("Cloyd Lau · MIT License") }
                }
            }.font(.caption).foregroundStyle(secondary)
        }
        .padding(18).frame(width: width).background(scheme == .dark ? Color.black : Color.white)
        .foregroundColor(scheme == .dark ? Color.white : Color.black)
        .environment(\.colorScheme, scheme).environment(\.locale, store.language.locale)
        .transaction { transaction in
            transaction.animation = nil
            transaction.disablesAnimations = true
        }
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        renderer.isOpaque = true
        return renderer.cgImage
    }
    private var screenshotDownloadCredit: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let appStoreURL {
                Text(tr("Download \(store.language.appName) on the App Store", "在 App Store 下载\(store.language.appName)"))
                    .fontWeight(.semibold)
                Text(appStoreURL.absoluteString.replacingOccurrences(of: "https://", with: ""))
                    .font(.system(size: 12, design: .monospaced))
            } else {
                Text("\(store.language.appName) · iPhone / iPad")
            }
        }.fixedSize(horizontal: false, vertical: true)
    }
    private func copyScreenshot() {
        guard let cgImage = renderLeaderboardImage(scheme: colorScheme) else {
            showNote(tr("Screenshot failed", "截图失败"))
            return
        }
        #if os(iOS)
        UIPasteboard.general.image = UIImage(cgImage: cgImage, scale: 2, orientation: .up)
        #if DEBUG
        // Retain the actual exported pixels for simulator review. The UI-test
        // runner cannot read another app's clipboard on current iOS versions.
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--ui-testing") && arguments.contains("--export-preview"),
           let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let file = directory.appending(path: "export-\(store.language.rawValue)-\(colorScheme == .dark ? "dark" : "light").png")
            try? UIImage(cgImage: cgImage).pngData()?.write(to: file)
        }
        #endif
        #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([NSImage(cgImage: cgImage, size: .zero)])
        #endif
        showNote(tr("Copied to clipboard", "已复制到剪贴板"), duration: 4)
    }
    #if os(iOS)
    private func saveScreenshotToPhotos() async {
        guard !presentation.savingScreenshot else { return }
        presentation.savingScreenshot = true
        defer { presentation.savingScreenshot = false }
        guard let cgImage = renderLeaderboardImage(scheme: colorScheme) else {
            showNote(tr("Screenshot failed", "截图失败"))
            return
        }
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            presentation.photoPermissionDenied = true
            return
        }
        let image = UIImage(cgImage: cgImage, scale: 2, orientation: .up)
        do {
            try await PHPhotoLibrary.shared().performChanges { @Sendable in
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            }
            showNote(tr("Saved to Photos", "已保存到相册"), duration: 4)
        } catch {
            showNote(tr("Save failed. Try again.", "保存失败，请重试。"))
        }
    }
    #endif
    #if DEBUG && os(iOS)
    private func writeDebugExportIfRequested() async {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("--ui-testing"), arguments.contains("--capture-export") else { return }
        // Let the native window apply its initial appearance before rendering.
        do { try await Task.sleep(for: .milliseconds(750)) } catch { return }
        guard let image = renderLeaderboardImage(scheme: arguments.contains("--dark") ? .dark : .light),
              let data = UIImage(cgImage: image).pngData() else { return }
        let url = URL.documentsDirectory.appending(path: "leaderboard-export.png")
        do { try data.write(to: url, options: .atomic) }
        catch { print("[preview] Export failed: \(error.localizedDescription)") }
    }
    #endif
    private func copyName(_ name: String) {
        #if os(iOS)
        UIPasteboard.general.string = name
        #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(name, forType: .string)
        #endif
        showNote(tr("Copied ", "已复制 ") + name)
    }
    private func showNote(_ note: String, duration: Double = 2.4) {
        presentation.note = note
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(duration))
            if presentation.note == note { presentation.note = nil }
        }
    }
}

@MainActor
private struct PadBoardCard: View {
    let kind: LeaderboardKind
    let board: Leaderboard?
    let rowPresentation: PadRowPresentation
    let grouping: LeaderboardGrouping
    let language: AppLanguage
    let filter: LeaderboardCountryFilter
    let opennessFilter: LeaderboardOpennessFilter
    let isRefreshing: Bool
    let isImage: Bool
    let compact: Bool
    let exportScheme: ColorScheme?
    let refresh: () -> Void
    let selectCountry: (LeaderboardCountryFilter) -> Void
    let selectOpenness: (LeaderboardOpennessFilter) -> Void
    let copyName: (String) -> Void
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var detail = PadBoardDetail()
    private func tr(_ en: String, _ zh: String) -> String { language.text(en, zh) }
    private var rows: [LeaderboardEntry] { rowPresentation.rows }
    private var displayScheme: ColorScheme { exportScheme ?? colorScheme }
    private var primaryForeground: Color { isImage ? (displayScheme == .dark ? .white : .black) : .primary }
    private var secondaryForeground: Color {
        guard isImage else { return .secondary }
        let level = displayScheme == .dark ? 0.6 : 0.5
        return Color(red: level, green: level, blue: level)
    }
    private var compactColumns: Bool {
        #if os(iOS)
        compact && !isImage && UIDevice.current.userInterfaceIdiom == .phone
        #else
        false
        #endif
    }
    private var columnSpacing: CGFloat { compactColumns ? 4 : 8 }
    private var columnPadding: CGFloat { compactColumns ? 6 : 8 }
    private var columnHeaderFont: Font { compactColumns ? .caption2 : .caption }
    @ScaledMetric(relativeTo: .caption2) private var compactFilterHeaderSize: CGFloat = 10
    @ScaledMetric(relativeTo: .caption) private var regularFilterHeaderSize: CGFloat = 11
    private var filterHeaderFont: Font {
        .system(size: compactColumns ? compactFilterHeaderSize : regularFilterHeaderSize)
    }
    private var rankColumnWidth: CGFloat {
        compactColumns ? (language == .english ? 26 : 22) : (language == .english ? 28 : 24)
    }
    private var scoreWidthReference: String {
        rowPresentation.scoreWidthReference
    }
    // Size every cell from the same single-line value, including the header.
    // Measuring through Text also follows the font and locale used by exports.
    @ViewBuilder private func scoreColumn<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        let column = ZStack {
            Text(scoreWidthReference).font(compactColumns ? .caption : .subheadline).monospacedDigit().hidden()
            content()
        }.lineLimit(1).fixedSize(horizontal: true, vertical: false).frame(minWidth: compactColumns ? 32 : 44)
        if compactColumns { column.font(.caption) }
        else { column }
    }
    @ViewBuilder private var countryHeaderLabel: some View {
        filterHeader(Text(isImage && filter != .all ? filter.title(language: language) : tr("Country", "国家")))
    }
    private func countryColumn<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ZStack {
            countryHeaderLabel.hidden()
            content()
        }.lineLimit(1).fixedSize(horizontal: true, vertical: false).frame(minWidth: compactColumns ? 26 : 32)
    }
    private var filterChevron: some View {
        Image(systemName: "chevron.down")
            .font(.system(size: (compactColumns ? compactFilterHeaderSize : regularFilterHeaderSize) * 0.65, weight: .medium))
    }
    @ViewBuilder
    private func filterHeader(_ title: Text) -> some View {
        if isImage {
            title.font(filterHeaderFont)
        } else {
            // Native Menu labels retain these balanced slots when composing their title.
            HStack(spacing: 1) {
                filterChevron.opacity(0).accessibilityHidden(true)
                title
                filterChevron
            }.font(filterHeaderFont)
        }
    }
    private var opennessHeaderLabel: some View {
        filterHeader(Text(isImage && opennessFilter != .all ? opennessFilter.title(language: language) : ModelOpenness.columnTitle(language: language)))
            .accessibilityIdentifier("openness-header-\(kind.rawValue)")
    }
    private func opennessColumn<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ZStack {
            opennessHeaderLabel.hidden()
            ModelOpennessBadge(.closed, language: language, colorScheme: displayScheme,
                showsTitle: !compactColumns).hidden()
            content()
        }.lineLimit(1).fixedSize(horizontal: true, vertical: false)
    }
    var body: some View {
        if isImage { cardContent }
        else { interactiveCard }
    }
    @ViewBuilder private var timeLabels: some View {
        if compactColumns {
            Text(LeaderboardPresentation.displayTime(board, language: language))
                .font(.caption2).monospacedDigit().foregroundStyle(secondaryForeground)
                .lineLimit(1).fixedSize().accessibilityIdentifier("source-times-\(kind.rawValue)")
        } else { detailedTimeLabels }
    }
    private var detailedTimeLabels: some View {
        let times = LeaderboardPresentation.sourceTimes(board, language: language)
        return ViewThatFits(in: .horizontal) {
            ZStack(alignment: .trailing) {
                Text(tr("Updated 12/31 23:59 · Fetched 12/31 23:59", "更新 12/31 23:59 · 抓取 12/31 23:59")).hidden()
                HStack(spacing: 5) {
                    Text(times.updated)
                    Text("·").foregroundStyle(secondaryForeground.opacity(0.5))
                    Text(times.fetched)
                }
            }.fixedSize()
            VStack(alignment: .trailing, spacing: 4) {
                Text(times.updated)
                Text(times.fetched)
            }.fixedSize(horizontal: true, vertical: false)
        }
        .font(compactColumns ? .caption2 : .caption).monospacedDigit()
        .foregroundStyle(secondaryForeground)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(times.updated + " · " + times.fetched)
        .accessibilityIdentifier("source-times-\(kind.rawValue)")
    }
    private var sourceDescription: some View {
        Text(LeaderboardPresentation.sourceSummary(kind, language: language))
            .foregroundStyle(secondaryForeground)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("source-summary-\(kind.rawValue)")
    }
    @ViewBuilder private var sourceMetadata: some View {
        HStack(alignment: .top, spacing: 12) {
            if isImage { sourceDescription }
            else {
                Button { detail.showingSource = true } label: { sourceDescription }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("source-help-\(kind.rawValue)")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if isImage { timeLabels }
            else {
                Button(action: refresh) { timeLabels }
                    .buttonStyle(.plain).disabled(isRefreshing)
                    .accessibilityHint(tr("Tap to refresh. Source update may be unavailable.", "点击刷新；来源可能不提供更新时间。"))
                    .accessibilityIdentifier("refresh")
                    .help(LeaderboardPresentation.sourceTimeHelp(board, language: language))
            }
        }.font(.caption)
    }
    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                if isImage {
                    Text(LeaderboardPresentation.title(kind, language: language))
                        .font(.subheadline.weight(.medium)).foregroundStyle(primaryForeground)
                }
                sourceMetadata
            }.padding(.horizontal, columnPadding).padding(.vertical, 12)
            HStack(spacing: columnSpacing) {
                Text(tr("Rank", "排名")).lineLimit(1).frame(width: rankColumnWidth)
                Text(kind.sourceLinkTitle)
                    .font(columnHeaderFont.weight(.semibold))
                    .foregroundStyle(kind.sourcePrefix == "Arena" ? Color.purple : Color.blue)
                    .lineLimit(1).minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("source-heading-\(kind.rawValue)")
                if isImage { countryColumn { countryHeaderLabel } }
                else {
                    countryColumn {
                        Menu {
                            ForEach(rowPresentation.countries, id: \.self) { option in
                                Button { selectCountry(option) } label: {
                                    if option == filter { Label(option.title(language: language), systemImage: "checkmark") }
                                    else { Text(option.title(language: language)) }
                                }
                            }
                        } label: { countryHeaderLabel }
                        .buttonStyle(.plain).accessibilityIdentifier("country-\(kind.rawValue)")
                        .accessibilityValue(filter.title(language: language))
                    }
                }
                opennessColumn {
                    if isImage { opennessHeaderLabel }
                    else {
                        Menu {
                            ForEach(LeaderboardOpennessFilter.allCases, id: \.self) { option in
                                Button { selectOpenness(option) } label: {
                                    if option == opennessFilter { Label(option.title(language: language), systemImage: "checkmark") }
                                    else { Text(option.title(language: language)) }
                                }.accessibilityIdentifier("openness-option-\(kind.rawValue)-\(option.rawValue)")
                            }
                        } label: { opennessHeaderLabel }
                        .buttonStyle(.plain).accessibilityIdentifier("openness-filter-\(kind.rawValue)")
                        .accessibilityValue(opennessFilter.title(language: language))
                        .foregroundStyle(opennessFilter == .all ? secondaryForeground : Color.accentColor)
                        .help(ModelOpenness.help(language: language))
                    }
                }
                scoreColumn { Text(tr("Score", "分数")).font(columnHeaderFont) }
            }.font(columnHeaderFont).foregroundStyle(secondaryForeground).padding(.horizontal, columnPadding)
                .padding(.top, 12).padding(.bottom, 8)
            Divider()
            if board != nil {
                if rows.isEmpty { Text("-").foregroundStyle(.secondary).padding(16) }
                if isImage {
                    // Exports need the entire image, including offscreen rows.
                    PadBoardRowsLayout {
                        ForEach(rows.indices, id: \.self) { index in rankingRow(rows[index], index: index) }
                    }
                } else {
                    // Keep the existing measured heading gap from the first two
                    // rows. All remaining live rows are created near the viewport.
                    PadBoardRowsLayout {
                        ForEach(rows.indices.prefix(2), id: \.self) { index in rankingRow(rows[index], index: index) }
                    }
                    LazyVStack(spacing: 0) {
                        ForEach(rows.indices.dropFirst(2), id: \.self) { index in
                            rankingRow(rows[index], index: index)
                        }
                    }
                }
            } else {
                ForEach(1...20, id: \.self) { rank in
                    HStack(spacing: columnSpacing) {
                        Text(LeaderboardPresentation.rankLabel(rank)).frame(width: rankColumnWidth)
                        Spacer()
                        countryColumn { Text("-") }
                        opennessColumn { Text("—").font(.caption) }
                        scoreColumn { Text("-") }
                    }
                        .font(.subheadline).foregroundStyle(.secondary).padding(.horizontal, columnPadding).padding(.vertical, 8)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(isImage ? (displayScheme == .dark ? Color.black : Color.white) : Color.padCard, in: RoundedRectangle(cornerRadius: 6))
        .accessibilityElement(children: .contain).accessibilityIdentifier("board-\(kind.rawValue)")
    }
    private var interactiveCard: some View {
        cardContent
        .sheet(isPresented: $detail.showingSource) {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if compact { Text(LeaderboardPresentation.title(kind, language: language)).font(.headline).fixedSize(horizontal: false, vertical: true) }
                        Text(sourceDetails)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(24)
                }
                    .navigationTitle(compact ? kind.sourceLinkTitle : LeaderboardPresentation.title(kind, language: language))
                    #if os(iOS)
                    .navigationBarTitleDisplayMode(.inline)
                    #endif
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button(tr("Done", "完成")) { detail.showingSource = false } } }
            }
        }
        .sheet(isPresented: Binding(get: { detail.selectedCompany != nil }, set: { if !$0 { detail.selectedCompany = nil } })) {
            NavigationStack {
                ScrollView {
                    if let standing = detail.selectedCompany { Text(CompanyLeaderboard.scoreHelp(for: standing, language: language)).frame(maxWidth: .infinity, alignment: .leading).padding(24) }
                }.navigationTitle(detail.selectedCompany?.entry.name ?? "")
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button(tr("Done", "完成")) { detail.selectedCompany = nil } } }
            }
        }
    }

    private func rankingRow(_ entry: LeaderboardEntry, index: Int) -> some View {
        entryRow(entry, rank: index + 1).id(PadComparisonScrollTarget.rank(index + 1))
            .background {
                if compact && !isImage {
                    GeometryReader { geometry in
                        let frame = geometry.frame(in: .named("rank-scroll-\(kind.rawValue)"))
                        Color.clear.preference(key: LeaderboardRankFrames.self,
                            value: [index + 1: LeaderboardRankFrame(minY: frame.minY, maxY: frame.maxY)])
                    }
                }
            }
    }

    private var sourceDetails: String {
        LeaderboardPresentation.sourceHelp(kind, language: language, board: board)
    }

    private func entryRow(_ entry: LeaderboardEntry, rank: Int) -> some View {
        let country = OrganizationRegion.country(for: entry)
        return HStack(alignment: .center, spacing: columnSpacing) {
            Text(LeaderboardPresentation.rankLabel(rank)).font(compactColumns ? .caption : .subheadline)
                .monospacedDigit().foregroundStyle(primaryForeground).frame(width: rankColumnWidth)
            HStack(spacing: 6) {
                PadOrganizationLogo(entry: entry, isCompany: grouping == .company)
                if compact && grouping == .company {
                    HStack(alignment: compactColumns ? .center : .firstTextBaseline, spacing: 6) {
                        entryName(entry)
                        purchaseLinks(entry)
                    }
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    entryName(entry)
                    if grouping == .company { purchaseLinks(entry) }
                }
            }.padding(.horizontal, 5).padding(.vertical, 3)
                // Fill the 44-point minimum row, leaving 4 points on each side.
                .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
                .background(brandColor(entry).opacity(0.34), in: RoundedRectangle(cornerRadius: 5))
                .alignmentGuide(.padNameTop) { $0[.top] }
                .padding(.vertical, 4)
            countryColumn { Text(country?.flagEmoji ?? "-").foregroundStyle(primaryForeground) }
                .accessibilityLabel(country?.localizedName(language: language) ?? tr("Country unknown", "未知"))
            opennessColumn {
                ModelOpennessBadge(entry.openness, language: language, colorScheme: displayScheme,
                    showsTitle: !compactColumns,
                    accessibilityIdentifier: "openness-\(kind.rawValue)-\(entry.id)")
            }
            if grouping == .company && !isImage {
                Button { detail.selectedCompany = LeaderboardPresentation.companies(board, filter: filter, openness: opennessFilter).first { $0.entry.id == entry.id } } label: {
                    scoreColumn { Text(entry.score, format: .number.precision(.fractionLength(1))).monospacedDigit() }.frame(height: 44)
                }.buttonStyle(.plain).foregroundStyle(.secondary)
                .accessibilityLabel("\(entry.name), \(entry.score), \(tr("score details", "分数说明"))")
                .accessibilityIdentifier("score-\(kind.rawValue)-\(entry.id)")
            } else {
                scoreColumn { Text(entry.score, format: .number.precision(.fractionLength(1))).monospacedDigit().foregroundStyle(secondaryForeground) }
            }
        }
        .font(.subheadline).padding(.horizontal, columnPadding).frame(minHeight: 44)
        .background(rank.isMultiple(of: 2) ? Color.secondary.opacity(0.05) : Color.clear)
    }
    @ViewBuilder private func entryName(_ entry: LeaderboardEntry) -> some View {
        if isImage { Text(entry.name).foregroundStyle(primaryForeground).fixedSize(horizontal: false, vertical: true) }
        else {
            #if os(iOS)
            if compactColumns {
                PhoneLeaderboardName(name: entry.name, language: language,
                    identifier: "name-\(kind.rawValue)-\(entry.id)", copyName: copyName)
            } else { copyableEntryName(entry) }
            #else
            copyableEntryName(entry)
            #endif
        }
    }
    private func copyableEntryName(_ entry: LeaderboardEntry) -> some View {
        Button { copyName(entry.name) } label: {
            Text(entry.name).fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }.buttonStyle(.plain).accessibilityLabel(entry.name + tr(", click to copy", "，点击复制"))
            .accessibilityIdentifier("name-\(kind.rawValue)-\(entry.id)")
    }
    private func purchaseLinks(_ entry: LeaderboardEntry) -> some View {
        let links = PurchaseLinkCatalog.links(forOrganization: entry.organization, modelName: entry.name)
        let usageTitle = tr(compact ? "Usage" : "Pay as you go", "按量")
        return HStack(spacing: 8) {
            if let link = PurchaseLinkCatalog.preferredLink(from: links.codingPlan, language: language) {
                if isImage { Text(tr("Plan", "套餐")) } else { Link(tr("Plan", "套餐"), destination: link.url) }
            }
            if let link = PurchaseLinkCatalog.preferredLink(from: links.payAsYouGo, language: language) {
                if isImage { Text(usageTitle) } else { Link(usageTitle, destination: link.url) }
            }
        }.font(.caption).fixedSize()
    }
    private func brandColor(_ entry: LeaderboardEntry) -> Color {
        let raw = OrganizationLogoCatalog.rowBrandColorHex(for: entry)
        let display = OrganizationLogoCatalog.displayBrandColorHex(raw, isDark: displayScheme == .dark, modelName: grouping == .model ? entry.name : nil)
        let value = UInt32(display.dropFirst(), radix: 16) ?? 0
        return Color(red: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255)
    }
}

private struct PadOrganizationLogo: View {
    let entry: LeaderboardEntry
    let isCompany: Bool
    private var image: Image? {
        if let data = OrganizationLogoCatalog.rowLogoPNGData(for: entry, isCompany: isCompany) {
            #if os(iOS)
            if let image = UIImage(data: data) { return Image(uiImage: image) }
            #else
            if let image = NSImage(data: data) { return Image(nsImage: image) }
            #endif
        }
        guard let key = OrganizationLogoCatalog.bundledLogoKey(forOrganization: entry.organization, modelName: entry.name),
              let image = Self.image(for: key) else { return nil }
        return image
    }
    static func image(for key: String) -> Image? {
        guard let url = Bundle.main.url(forResource: key, withExtension: "png", subdirectory: "logos") else { return nil }
        #if os(iOS)
        return UIImage(contentsOfFile: url.path).map(Image.init(uiImage:))
        #else
        return NSImage(contentsOf: url).map(Image.init(nsImage:))
        #endif
    }
    var body: some View {
        Group {
            if let image { image.resizable().scaledToFit() }
            else {
                Text(OrganizationLogoCatalog.initial(organization: entry.organization, modelName: entry.name))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.black.opacity(0.65))
            }
        }
        .padding(2.5)
        .frame(width: 20, height: 20)
        .background(.white, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .strokeBorder(.quaternary, lineWidth: 0.5)
        }
        .accessibilityHidden(true)
    }
}
private struct PadLeaderboardScrollEdges: ViewModifier {
    var edges: Edge.Set = .vertical
    @ViewBuilder func body(content: Content) -> some View {
        #if os(iOS) && compiler(>=6.2)
        if #available(iOS 26.0, *) {
            // The cube header sits outside its scroll view; the wide layout
            // retains its system top edge. Neither needs a bottom edge blur.
            content.scrollEdgeEffectHidden(true, for: edges)
        } else {
            content
        }
        #else
        content
        #endif
    }
}

private extension Color {
    static var padBackground: Color {
        #if os(iOS)
        Color(uiColor: .systemBackground)
        #else
        Color(nsColor: .windowBackgroundColor)
        #endif
    }
    static var padCard: Color { padBackground }
}

#if os(iOS)
/// Explicit segment widths match the desktop control and remain stable across
/// SwiftUI measurement probes, rotation and screenshot-feedback updates.
@MainActor
private struct PadSegmentedControl<Value: Hashable>: UIViewRepresentable {
    let values: [Value]
    let titles: [String]
    @Binding var selection: Value
    let identifier: String
    let label: String
    var segmentWidth: CGFloat = 90
    var fontSize: CGFloat? = nil

    func makeCoordinator() -> Coordinator { Coordinator(values: values, selection: $selection) }
    func makeUIView(context: Context) -> UISegmentedControl {
        let control = UISegmentedControl(items: titles)
        control.apportionsSegmentWidthsByContent = false
        if let fontSize { control.setTitleTextAttributes([.font: UIFont.systemFont(ofSize: fontSize, weight: .medium)], for: .normal) }
        // Both fixed-width control groups allocate 90 points per option.
        // Do not change widths during layout: UIKit can invalidate its own
        // measurements repeatedly and block the main event loop.
        for index in titles.indices { control.setWidth(segmentWidth, forSegmentAt: index) }
        control.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .valueChanged)
        return control
    }
    func updateUIView(_ control: UISegmentedControl, context: Context) {
        context.coordinator.selection = $selection
        for (index, title) in titles.enumerated() where control.titleForSegment(at: index) != title {
            control.setTitle(title, forSegmentAt: index)
        }
        control.accessibilityIdentifier = identifier
        control.accessibilityLabel = label
        let index = values.firstIndex(of: selection) ?? UISegmentedControl.noSegment
        if control.selectedSegmentIndex != index { control.selectedSegmentIndex = index }
    }
    @MainActor
    final class Coordinator: NSObject {
        let values: [Value]
        var selection: Binding<Value>
        init(values: [Value], selection: Binding<Value>) { self.values = values; self.selection = selection }
        @objc func changed(_ control: UISegmentedControl) {
            guard values.indices.contains(control.selectedSegmentIndex) else { return }
            selection.wrappedValue = values[control.selectedSegmentIndex]
        }
    }
}
#endif
