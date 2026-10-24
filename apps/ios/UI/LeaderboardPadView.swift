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
    @Published var note: String?
    @Published var savingScreenshot = false
    @Published var photoPermissionDenied = false
    @Published var showingQuotaTrackingHelp = false
    @Published var pairScrolled = false
    @Published var showingAbout = false
    @Published var selectedModel: LeaderboardEntry?
    @Published var showingCapture = false
    @Published var generatingCapture = false
    @Published var generatedCapturePages = 0
    @Published var totalCapturePages = 1
    @Published var capturePaths: [URL] = []
    @Published var captureIndex = 0
    @Published var savedCapturePages = 0
}
// Keep scroll targets distinct from ForEach's zero-based integer identities.
private enum PadComparisonScrollTarget: Hashable {
    case top, rank(Int)
}
private struct PadRankingTop: PreferenceKey {
    static var defaultValue: CGFloat { 0 }
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
// Share the same clearance with the scroll content: at the end of a list the
// footer sits above the control, which sits above the bottom category bar.
private enum PadBottomControls {
    static let buttonBottom: CGFloat = 78
    static let footerPadding: CGFloat = buttonBottom + 44 + 16
}

@MainActor
private struct PadBackToTopControl<Control: View>: ViewModifier {
    let bottomInset: CGFloat
    let trailingInset: CGFloat
    let visible: Bool
    let control: Control

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottomTrailing) {
            if visible {
                control.offset(x: -trailingInset, y: -(bottomInset + PadBottomControls.buttonBottom))
            }
        }
    }
}
@MainActor
private struct PadCubeSourceTabs: ViewModifier {
    @ObservedObject var scroll: LeaderboardCubeScrollState
    func body(content: Content) -> some View {
        content.offset(y: -scroll.sourceTabsOffset)
            .allowsHitTesting(scroll.sourceTabsOffset < LeaderboardCubeScrollState.contentTopInset)
            .accessibilityHidden(scroll.sourceTabsOffset >= LeaderboardCubeScrollState.contentTopInset)
    }
}
@MainActor
private struct PadCubeBackToTopControl<Control: View>: ViewModifier {
    @ObservedObject var scroll: LeaderboardCubeScrollState
    let active: Bool
    let bottomInset: CGFloat
    let control: Control
    func body(content: Content) -> some View {
        content.modifier(PadBackToTopControl(bottomInset: bottomInset,
            trailingInset: 12, visible: active && scroll.canReturnToTop, control: control))
    }
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
    @ScaledMetric(relativeTo: .body) private var englishTitleFontSize: CGFloat = 21
    @StateObject private var presentation = PadPresentationState()
    public static let repositoryURL = URL(string: "https://github.com/cloydlau/ai-benchgauge")!
    private let appStoreURL: URL?

    @StateObject private var cube = LeaderboardCubeState()
    @State private var sourceDragIndex: Int?
    @GestureState private var cubeDragAxis = LeaderboardCube.DragAxis.undecided
    public init(store: LeaderboardPadStore,
                appStoreID: String? = Bundle.main.object(forInfoDictionaryKey: "BenchGaugeAppStoreID") as? String) {
        self.store = store
        let initialCube = LeaderboardCubeState(position: Double(store.selectedSource))
        initialCube.face = store.selectedSource
        _cube = StateObject(wrappedValue: initialCube)
        if let appStoreID, appStoreID.first.map({ "123456789".contains($0) }) == true,
           appStoreID.allSatisfy({ "0123456789".contains($0) }) {
            self.appStoreURL = URL(string: "https://apps.apple.com/app/id\(appStoreID)")
        } else { self.appStoreURL = nil }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--cube-preview") {
            let preview = LeaderboardCubeState()
            preview.finishEntrance()
            let position = Double(ProcessInfo.processInfo.environment["BENCHGAUGE_UI_CUBE_POSITION"] ?? "") ?? 0.5
            preview.position = position.isFinite ? min(1, max(0, position)) : 0.5
            _cube = StateObject(wrappedValue: preview)
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
    private func tr(_ en: String, _ zh: String) -> String { store.language.text(en, zh) }

    public var body: some View {
        GeometryReader { geometry in
            let layout = MobileLeaderboardLayout(width: geometry.size.width, boardCount: store.category.boardKinds.count)
            Group {
                if layout.usesCube {
                    VStack(alignment: .leading, spacing: 12) {
                        mobileHeader
                        cubeBoards(bottomInset: geometry.safeAreaInsets.bottom)
                    }
                    .padding(.horizontal, 12).padding(.top, 8)
                    .ignoresSafeArea(.container, edges: .bottom)
                    .task(id: store.selectedKind) { await store.refresh() }
                } else {
                    pairedBoards(layout: layout, bottomInset: geometry.safeAreaInsets.bottom, viewportHeight: geometry.size.height)
                }
            }
            .onChange(of: geometry.size) { _, _ in
                // Settle interrupted gestures without resetting the selected source,
                // query or persisted filters as the window folds, unfolds or rotates.
                var transaction = Transaction(); transaction.disablesAnimations = true
                withTransaction(transaction) {
                    cancelCubeEntrance()
                    sourceDragIndex = nil
                    cube.finishTurn()
                }
            }
        }
        .tint(BrandTheme.accent(for: colorScheme))
        .accentColor(BrandTheme.accent(for: colorScheme))
        .background { Color.padBackground.ignoresSafeArea() }
        .overlay(alignment: .bottom) {
            MobileCategoryBar(category: $store.category, language: store.language,
                accent: sourceTabColor(SourceTabTheme.palette(for: store.category.boardKinds[
                    min(max(0, sourceDragIndex ?? cube.face), store.category.boardKinds.count - 1)],
                    dark: colorScheme == .dark).accent), select: cancelCubeEntrance)
                .padding(.bottom, 8)
        }
        .overlay(alignment: .bottom) {
            if let note = presentation.note {
                Text(note).font(.footnote).padding(12)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8)).padding(20).padding(.bottom, 80)
            }
        }
        .overlay {
            if presentation.generatingCapture {
                VStack(spacing: 12) {
                    Text(tr("Generating images", "正在生成图片"))
                    ProgressView(value: Double(presentation.generatedCapturePages), total: Double(presentation.totalCapturePages))
                    Text("\(presentation.generatedCapturePages) / \(presentation.totalCapturePages)").monospacedDigit()
                }.font(.subheadline).frame(width: 180).padding(24)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                    .accessibilityIdentifier("capture-progress")
            }
        }
        // Keep the floating categories at the screen bottom, underneath the keyboard.
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .sheet(isPresented: $presentation.showingAbout) { aboutSheet }
        .sheet(item: $presentation.selectedModel) { entry in
            ModelDetailsView(entry: entry, language: store.language,
                copyName: { name in copyName(name); return true }, close: { presentation.selectedModel = nil })
                #if os(iOS)
                .presentationDetents([.large]).presentationDragIndicator(.visible)
                #else
                .frame(width: 560, height: 620)
                #endif
        }
        #if os(iOS)
        .sheet(isPresented: $presentation.showingCapture, onDismiss: clearCapturedPages) { screenshotPreview }
        #endif
        .alert(tr("Feature overview", "功能说明"), isPresented: $presentation.showingQuotaTrackingHelp) {
            Button(tr("Got it", "知道了"), role: .cancel) { }
        } message: {
            Text(AppFeatureCopy.subtitle(language: store.language) + "\n\n" + AppFeatureCopy.quotaMessage(language: store.language))
        }
        #if DEBUG && os(iOS)
        .task { await writeDebugExportIfRequested() }
        #endif
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
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

    private var mobileHeader: some View {
        GeometryReader { geometry in
            let sizing = MobileBrandSizing(language: store.language, width: geometry.size.width,
                controlsWidth: mobileGroupingWidth)
            mobileInlineHeader(sizing: sizing)
        }.frame(height: 44)
    }
    private func mobileInlineHeader(sizing: MobileBrandSizing) -> some View {
        HStack(spacing: 0) {
            HStack(spacing: sizing.titleCaptionSpacing) {
                mobileBrandTitle(size: sizing.titleFontSize).fixedSize(horizontal: true, vertical: false)
                if sizing.showsSubtitle { featureHelp(sizing: sizing) }
            }
            Spacer(minLength: MobileBrandSizing.controlsSpacing)
            mobileGrouping
        }
    }
    private var mobileGroupingWidth: CGFloat { store.language == .english ? 160 : 104 }
    @ViewBuilder private var mobileGrouping: some View {
        #if os(iOS)
        let width = mobileGroupingWidth
        PadSegmentedControl(values: LeaderboardGrouping.allCases,
            titles: [tr("Models", "模型"), tr("Companies", "公司")], selection: $store.grouping,
            identifier: "grouping", label: tr("Grouping", "分组"), segmentWidth: width / 2, fontSize: 11)
            .frame(width: width, height: 30).id(width)
        #else
        groupingPicker.frame(width: 160)
        #endif
    }
    private func mobileBrandTitle(size: CGFloat) -> some View {
        let ink = store.language == .english ? Self.textInkBounds(store.language.appName,
            font: CTFontCreateWithName("SnellRoundhand-Bold" as CFString, size, nil)) : nil
        let inkHeight = BrandTitleMetrics.inkHeight(language: store.language, fontSize: size)
        return Group {
                if store.language == .english { appTitle(fontSize: size) }
                else { appTitle.scaleEffect(size / 21, anchor: .leading)
                    .frame(width: BrandTitleMetrics.layoutWidth(language: store.language, fontSize: size), alignment: .leading) }
        }.frame(height: 44)
                .alignmentGuide(.padTitleInkTop) { dimensions in
                    ink.map { dimensions[.firstTextBaseline] - $0.maxY } ?? (dimensions.height - inkHeight) / 2
                }
                .alignmentGuide(.padTitleInkBottom) { dimensions in
                    ink.map { dimensions[.firstTextBaseline] - $0.minY } ?? (dimensions.height + inkHeight) / 2
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(store.language.appName)
                .accessibilityAddTraits(.isStaticText)
                .accessibilityIdentifier("brand-title")
    }
    private func featureHelp(sizing: MobileBrandSizing) -> some View {
        Button { presentation.showingQuotaTrackingHelp = true } label: {
            let rows = AppFeatureCopy.subtitleRows(language: store.language)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    Text(row).font(.system(size: sizing.subtitleFontSize, weight: .medium))
                        .lineLimit(1).fixedSize(horizontal: true, vertical: true)
                        .overlay(alignment: .trailing) {
                            if index == rows.count - 1 {
                                Image(systemName: "questionmark.circle")
                                    .resizable().scaledToFit()
                                    // Keep the mini-program's 1em icon size. SwiftUI compresses trailing
                                    // punctuation, so anchor after the actual text instead of its spare em.
                                    .frame(width: sizing.subtitleFontSize, height: sizing.subtitleFontSize)
                                    .opacity(0.55)
                                    .offset(x: sizing.subtitleFontSize)
                                    .accessibilityHidden(true)
                            }
                        }
                        .frame(height: sizing.subtitleHeight / 2, alignment: .leading)
                }
            }
            .frame(width: sizing.subtitleWidth, height: 44, alignment: .leading)
            .foregroundStyle(.secondary).contentShape(Rectangle())
        }.buttonStyle(.plain)
            .accessibilityIdentifier("quota-tracking-help")
            .accessibilityLabel(AppFeatureCopy.subtitle(language: store.language))
    }
    private var aboutSheet: some View {
        PadAboutView(language: store.language, brand: appTitle(fontSize: 24),
                     copyLink: copyName, dismiss: { presentation.showingAbout = false },
                     cloudbaseSourceNote: store.snapshot.boards[.cloudbaseUsage]?.sourceNote,
                     vercelSourceNote: store.snapshot.boards[.vercelUsage]?.sourceNote,
                     openRouterSourceNote: store.snapshot.boards[.openRouterUsage]?.sourceNote)
        .overlay(alignment: .bottom) {
            if let note = presentation.note { Text(note).font(.footnote).padding(12).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8)).padding(20) }
        }
        .accessibilityIdentifier("about-page")
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
    nonisolated private static func textInkBottom(_ dimensions: ViewDimensions, text: String, font: CTFont) -> CGFloat {
        let ink = textInkBounds(text, font: font)
        guard !ink.isNull, !ink.isEmpty else { return dimensions[.bottom] }
        return dimensions[.firstTextBaseline] - ink.minY
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

    @ViewBuilder private var cubeSelector: some View {
        if store.category == .usage && store.category.boardKinds.count == 1 {
            HStack(spacing: 8) {
                Text("OpenRouter").font(.caption.weight(.semibold))
                Text(LeaderboardPresentation.explanation(.openRouterUsage, language: store.language)).font(.caption)
            }.foregroundStyle(Color.primary).frame(maxWidth: .infinity, minHeight: 38)
                .background(Color.padBackground).accessibilityIdentifier("usage-source")
        } else {
        let selectedIndex = min(max(0, sourceDragIndex ?? cube.face), store.category.boardKinds.count - 1)
        let selectedKind = store.category.boardKinds[selectedIndex]
        let palette = SourceTabTheme.palette(for: selectedKind, dark: colorScheme == .dark)
        HStack(spacing: 6) {
            ForEach(Array(store.category.boardKinds.enumerated()), id: \.offset) { index, kind in
                Button { turnCube(to: index) } label: {
                    Text(kind.isUsage ? kind.sourcePrefix : LeaderboardPresentation.explanation(kind, language: store.language))
                        .font(.caption.weight(.semibold))
                        .lineLimit(2).frame(maxWidth: .infinity, minHeight: 38)
                        .foregroundStyle(selectedIndex == index ? sourceTabColor(palette.foreground) : Color.secondary)
                        .contentShape(Rectangle())
                }.buttonStyle(.plain).disabled(store.category.boardKinds.count == 1).accessibilityIdentifier("face-\(index)")
                    .accessibilityAddTraits(cube.face == index ? .isSelected : [])
            }
        }
        .modifier(MobileTabDrag(count: store.category.boardKinds.count, preview: $sourceDragIndex,
            enabled: store.category.boardKinds.count > 1 && !cube.turning && !store.modelSearchEditing, begin: cancelCubeEntrance) { turnCube(to: $0) })
        .background(alignment: .leading) {
            GeometryReader { geometry in
                let count = store.category.boardKinds.count
                let tabWidth = (geometry.size.width - CGFloat(count - 1) * 6) / CGFloat(count)
                RoundedRectangle(cornerRadius: 8)
                    .fill(sourceTabColor(palette.background))
                    .frame(width: tabWidth)
                    .offset(x: CGFloat(selectedIndex) * (tabWidth + 6))
            }
            .allowsHitTesting(false)
        }
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
        // Keep the rotating faces' shading behind the stationary tab bar.
        .background(Color.padBackground)
        .animation(usesReducedMotion ? nil : .timingCurve(0.22, 0.7, 0.2, 1, duration: 0.32), value: cube.face)
        }
    }
    private func sourceTabColor(_ hex: String) -> Color {
        let value = UInt32(hex.dropFirst(), radix: 16) ?? 0
        return Color(red: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255)
    }
    private func resetComparison() {
        cancelCubeEntrance()
        store.modelSearchEditing = false
        cube.scroll.reset()
        cube.generation += 1
        var transaction = Transaction(); transaction.disablesAnimations = true
        withTransaction(transaction) {
            cube.face = min(cube.face, store.category.boardKinds.count - 1)
            cube.finishTurn()
            store.selectedSource = cube.face
        }
    }
    private func turnCube(to face: Int, position: Int? = nil) {
        cancelCubeEntrance()
        var transaction = Transaction(); transaction.disablesAnimations = true
        if cube.turning { withTransaction(transaction) { cube.finishTurn() } }
        let count = store.category.boardKinds.count
        let target = position ?? LeaderboardCube.target(face: cube.face, destination: face, count: count)
        if !cube.dragging { cube.origin = cube.face }
        if target != cube.origin { cube.direction = target > cube.origin ? 1 : -1 }
        cube.dragging = false
        cube.turnSerial += 1
        let serial = cube.turnSerial
        cube.turning = true
        cube.face = LeaderboardCube.normalized(face, count: count)
        store.selectedSource = cube.face
        withAnimation(.easeInOut(duration: usesReducedMotion ? 0.18 : 0.42)) {
            cube.position = Double(target)
        } completion: {
            withTransaction(transaction) { cube.finishTurn(serial) }
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
        guard cubeContentReady, scenePhase == .active else { return }
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--cube-entrance-preview") {
            guard cube.beginEntrance(reduceMotion: usesReducedMotion) != nil else { return }
            cube.entranceProgress = 1
            if !usesReducedMotion { cube.position = Double(cube.face) + (cube.face == 0 ? 0.28 : -0.28) }
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
                if !usesReducedMotion { cube.position = Double(cube.face) + (cube.face == 0 ? 0.28 : -0.28) }
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
            .simultaneousGesture(DragGesture(minimumDistance: 8)
                .updating($cubeDragAxis) { value, axis, _ in
                    let next = LeaderboardCube.dragAxis(current: axis, x: value.translation.width, y: value.translation.height)
                    if axis != next { axis = next }
                }
                .onChanged { value in
                    cancelCubeEntrance()
                    guard store.category.boardKinds.count > 1, !cube.turning, !store.modelSearchEditing else { return }
                    guard LeaderboardCube.dragAxis(current: cubeDragAxis, x: value.translation.width, y: value.translation.height) == .horizontal else { return }
                    cube.origin = cube.face
                    cube.direction = value.translation.width > 0 ? -1 : 1
                    cube.dragging = true
                    if !usesReducedMotion {
                        cube.position = LeaderboardCube.position(face: cube.face, translation: value.translation.width, width: geometry.size.width, count: store.category.boardKinds.count)
                    }
                }
                .onEnded { value in
                    guard cube.dragging else { return }
                    let target = LeaderboardCube.destination(face: cube.face, translation: value.translation.width,
                        predicted: value.predictedEndTranslation.width, width: geometry.size.width, count: store.category.boardKinds.count)
                    turnCube(to: target, position: target)
                })
            .onChange(of: cubeDragAxis) { _, axis in
                // GestureState also resets on cancellation, so the next touch
                // starts fresh and an interrupted turn returns to its face.
                if axis == .undecided && cube.dragging { turnCube(to: cube.face) }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            // Flatten the projected scroll layers before applying the viewport
            // clip, so their perspective edges cannot escape into the heading.
            .compositingGroup()
            .id(cube.generation)
            .opacity(0.65 + cube.entranceProgress * 0.35)
            .scaleEffect(usesReducedMotion ? 1 : 0.985 + cube.entranceProgress * 0.015)
            .offset(y: usesReducedMotion ? 0 : (1 - cube.entranceProgress) * 12)
            .clipped()
            .overlay(alignment: .top) {
                cubeSelector.modifier(PadCubeSourceTabs(scroll: cube.scroll))
            }
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
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("cube-viewport")
            .accessibilityLabel(LeaderboardPresentation.title(store.category, language: store.language))
            .accessibilityValue(store.category.boardKinds[min(cube.face, store.category.boardKinds.count - 1)].sourceLinkTitle)
            .accessibilityHint(tr("Scroll vertically to explore; switch boards horizontally.", "上下滚动查看，左右切换榜单。"))
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: turnCube(to: cube.face + 1, position: cube.face + 1)
                case .decrement: turnCube(to: cube.face - 1, position: cube.face - 1)
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
                .contentShape(Circle())
                .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tr("Back to top", "返回顶部"))
        .accessibilityIdentifier("leaderboard-back-to-top")
    }

    private func pairedBoards(layout: MobileLeaderboardLayout, bottomInset: CGFloat, viewportHeight: CGFloat) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    mobileHeader.id(PadComparisonScrollTarget.top)
                        .background {
                            GeometryReader { geometry in
                                Color.clear.preference(key: PadRankingTop.self,
                                    value: geometry.frame(in: .named("paired-rankings")).minY)
                            }
                        }
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 0), spacing: MobileLeaderboardLayout.spacing, alignment: .top), count: layout.columns),
                              alignment: .leading, spacing: MobileLeaderboardLayout.spacing) {
                        ForEach(store.category.boardKinds, id: \.self) { kind in
                            boardCard(kind, denseColumns: layout.usesCompactColumns, viewportHeight: viewportHeight)
                                .task { await store.refresh(kind: kind) }
                        }
                    }
                    distributionPanels
                    compactFooter
                }
                .padding(.horizontal, MobileLeaderboardLayout.inset).padding(.top, 18)
                .padding(.bottom, bottomInset + PadBottomControls.footerPadding)
                .frame(maxWidth: MobileLeaderboardLayout.maximumContentWidth + MobileLeaderboardLayout.inset * 2)
                .frame(maxWidth: .infinity)
                .modifier(pullRefreshAttachment(store.selectedKind))
            }
            .coordinateSpace(name: "paired-rankings")
            .modifier(PadRankingScrollTracking { presentation.pairScrolled = $0 })
            .modifier(PadLeaderboardScrollEdges(edges: .bottom))
            .ignoresSafeArea(.container, edges: .bottom)
            // This overlay is inside the paired layout's safe-area bounds;
            // the phone cube's explicitly extended viewport needs its inset.
            .modifier(PadBackToTopControl(bottomInset: 0,
                trailingInset: 20, visible: presentation.pairScrolled,
                control: rankingBackToTop {
                        withAnimation(usesReducedMotion ? nil : .easeOut(duration: 0.25)) {
                            proxy.scrollTo(PadComparisonScrollTarget.top, anchor: .top)
                        }
                }))
        }
    }

    private func cubeFace(_ kind: LeaderboardKind, index: Int, size: CGSize, bottomInset: CGFloat) -> some View {
        let generation = cube.generation
        let hidesIndicator = cube.dragging || cube.turning || cube.entranceActive
            || abs(cube.position - Double(index)) > 0.0001
        return ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Color.clear.frame(height: LeaderboardCubeScrollState.contentTopInset - 10).id(PadComparisonScrollTarget.top)
                    boardCard(kind, compact: true, viewportHeight: size.height)
                        .background {
                            GeometryReader { geometry in
                                let frame = geometry.frame(in: .named("rank-scroll-\(kind.rawValue)"))
                                Color.clear.preference(key: LeaderboardRankFrames.self,
                                    value: [0: LeaderboardRankFrame(minY: frame.minY, maxY: frame.maxY)])
                            }
                        }
                    LeaderboardDistributionCharts(entries: store.snapshot.boards[kind]?.entries ?? [], language: store.language)
                    compactFooter
                }
                .padding(.bottom, bottomInset + PadBottomControls.footerPadding)
                .modifier(pullRefreshAttachment(kind, topSpacer: LeaderboardCubeScrollState.contentTopInset,
                    enabled: index == cube.face && !cube.dragging && !cube.turning && !cube.entranceActive))
            }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: store.modelSearchQuery) { _, _ in
                    guard store.grouping == .model, cube.scroll.canReturnToTop else { return }
                    var transaction = Transaction(); transaction.disablesAnimations = true
                    withTransaction(transaction) { proxy.scrollTo("model-header-\(kind.rawValue)", anchor: .top) }
                }
                // UIKit's scroll indicator should not become a projected cube edge.
                .scrollIndicators(hidesIndicator ? .hidden : .automatic, axes: .vertical)
                .modifier(PadLeaderboardScrollEdges())
                .coordinateSpace(name: "rank-scroll-\(kind.rawValue)")
                .onPreferenceChange(LeaderboardRankFrames.self) { frames in
                    Task { @MainActor in
                        guard generation == cube.generation, index == cube.face,
                              !cube.dragging && !cube.turning && !cube.entranceActive else { return }
                        cube.scroll.update(frames: frames, height: size.height)
                    }
                }
                .onChange(of: cube.dragging) { _, dragging in
                    // Align the incoming board before it rotates into view.
                    // Waiting for face selection exposes its top/tab spacer
                    // throughout the drag when the outgoing board is scrolled.
                    if dragging && index != cube.face { alignCubeFace(proxy, height: size.height) }
                }
                .onChange(of: cube.face) { _, face in
                    if face == index { alignCubeFace(proxy, height: size.height) }
                }
                .frame(width: size.width, height: size.height)
                .modifier(PadCubeBackToTopControl(scroll: cube.scroll,
                    active: index == cube.face, bottomInset: bottomInset,
                    control: rankingBackToTop {
                            withAnimation(usesReducedMotion ? nil : .easeOut(duration: 0.25)) {
                                proxy.scrollTo(PadComparisonScrollTarget.top, anchor: .top)
                            }
                    }))
                .background(Color.padBackground)
                .modifier(CubeFace(position: cube.position, face: LeaderboardCube.renderedFace(index, origin: cube.origin, direction: cube.direction, count: store.category.boardKinds.count), width: size.width, reduceMotion: usesReducedMotion))
                .disabled(index != cube.face || cube.dragging || cube.turning)
                .allowsHitTesting(index == cube.face && !cube.dragging && !cube.turning)
                .accessibilityHidden(index != cube.face || cube.dragging)
        }
    }
    private func pullRefreshAttachment(_ kind: LeaderboardKind, topSpacer: CGFloat = 0, enabled: Bool = true) -> MobilePullRefreshContent {
        MobilePullRefreshContent(enabled: enabled && !store.modelSearchEditing, topSpacer: topSpacer,
            identifier: "pull-refresh-\(kind.rawValue)", loadingLabel: tr("Loading", "加载中")) {
                await store.refresh(kind: kind, force: true)
            }
    }
    private func alignCubeFace(_ proxy: ScrollViewProxy, height: CGFloat) {
        guard let rank = cube.scroll.rank else { return }
        var transaction = Transaction(); transaction.disablesAnimations = true
        let target: PadComparisonScrollTarget = rank == 0 ? .top : .rank(rank)
        let inset = cube.scroll.columnHeaderHeight + 4
        let anchor = rank == 0 ? UnitPoint.top : UnitPoint(x: 0.5,
            y: min(1, inset / max(1, height - cube.scroll.comparisonRowHeight)))
        withTransaction(transaction) { proxy.scrollTo(target, anchor: anchor) }
    }
    private var distributionPanels: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 12, alignment: .top)], alignment: .leading, spacing: 12) {
            ForEach(store.category.boardKinds, id: \.self) { kind in
                LeaderboardDistributionCharts(entries: store.snapshot.boards[kind]?.entries ?? [], language: store.language,
                    boardTitle: LeaderboardPresentation.columnTitle(kind, language: store.language))
            }
        }
    }

    private var compactFooter: some View {
        HStack(spacing: 4) {
            Button { presentation.showingAbout = true } label: {
                Text(tr("About", "关于")).frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
            }.accessibilityIdentifier("about")
            Spacer(minLength: 8)
            #if os(iOS)
            PhoneMenuButton(title: "文/A", identifier: "language-menu",
                items: AppLanguage.allCases.map { language in
                    PhoneMenuItem(title: languageLabel(language), identifier: "language-\(language.rawValue)",
                        action: { store.language = language }, selected: language == store.language)
                }, label: tr("Language", "语言")).frame(width: 44, height: 44)
            #else
            Menu {
                ForEach(AppLanguage.allCases, id: \.self) { language in
                    Button(languageLabel(language)) { store.language = language }
                }
            } label: { Text("文/A").frame(width: 44, height: 44) }
                .accessibilityIdentifier("language-menu")
            #endif
            Menu {
                ForEach([("system", tr("System", "跟随系统")), ("light", tr("Light", "浅色")), ("dark", tr("Dark", "深色"))], id: \.0) { value, title in
                    Button { store.appearance = value } label: {
                        if store.appearance == value { Label(title, systemImage: "checkmark") }
                        else { Text(title) }
                    }
                }
            } label: { Image(systemName: "circle.lefthalf.filled").frame(width: 44, height: 44) }
                .accessibilityLabel(tr("Appearance", "外观")).accessibilityIdentifier("appearance-menu")
            #if !os(iOS)
            screenshotButton(compact: true).frame(width: 44, height: 44)
            #elseif DEBUG
            // Retain explicit export previews for development while the mobile entry is hidden.
            if ProcessInfo.processInfo.arguments.contains("--ui-testing"),
               ProcessInfo.processInfo.arguments.contains("--export-preview") {
                screenshotButton(compact: true).frame(width: 44, height: 44)
            }
            #endif
        }.font(.caption).buttonStyle(.plain).foregroundStyle(.secondary).lineLimit(1)
    }
    private func languageLabel(_ language: AppLanguage) -> String {
        switch language { case .english: "EN"; case .chinese: "简中"; case .traditionalChinese: "繁中" }
    }

    @ViewBuilder private func boardPair(wide: Bool, isImage: Bool = false, exportScheme: ColorScheme? = nil, pageRows: Range<Int>? = nil, viewportHeight: CGFloat = 900) -> some View {
        if wide {
            HStack(alignment: .top, spacing: 12) {
                ForEach(store.category.boardKinds, id: \.self) { kind in boardCard(kind, isImage: isImage, exportScheme: exportScheme, viewportHeight: viewportHeight, pageRows: pageRows) }
            }
        } else {
            VStack(spacing: 12) {
                ForEach(store.category.boardKinds, id: \.self) { kind in boardCard(kind, isImage: isImage, exportScheme: exportScheme, viewportHeight: viewportHeight, pageRows: pageRows) }
            }
        }
    }
    private func boardCard(_ kind: LeaderboardKind, isImage: Bool = false, compact: Bool = false, denseColumns: Bool = false, exportScheme: ColorScheme? = nil, viewportHeight: CGFloat = 900, pageRows: Range<Int>? = nil) -> some View {
        PadBoardCard(kind: kind, board: store.snapshot.boards[kind], rowPresentation: pageRows.map { store.rowPresentation(for: kind).page($0) } ?? store.rowPresentation(for: kind), grouping: store.grouping,
            language: store.language, filter: store.countryFilter(for: kind), opennessFilter: store.opennessFilter(for: kind),
            countryOptions: store.availableCountryFilters, skeletonHeight: viewportHeight,
            failure: store.failures[kind],
            modelSearchQuery: $store.modelSearchQuery, modelSearchPresented: $store.modelSearchPresented,
            modelSearchEditing: $store.modelSearchEditing,
            isRefreshing: store.refreshing.contains(kind), polishRevision: store.timestampPolishRevisions[kind, default: 0], isImage: isImage, compact: compact, denseColumns: denseColumns, exportScheme: exportScheme,
            selectCountry: { store.setCountryFilter($0, for: kind); resetComparison() },
            clearFilters: { store.modelSearchQuery = ""; store.setCountryFilter(.all, for: kind); store.setOpennessFilter(.all, for: kind); resetComparison() },
            selectOpenness: { store.setOpennessFilter($0, for: kind); resetComparison() }, openModel: { entry in
                cancelCubeEntrance()
                // A simultaneous cube drag can also release a name button.
                // Only a tap on a settled, stationary board may open details.
                guard !compact || (!cube.dragging && !cube.turning) else { return }
                presentation.selectedModel = entry
            })
    }

    @ViewBuilder private func screenshotButton(compact: Bool) -> some View {
        #if os(iOS)
        Button { Task { await prepareScreenshotPreview() } } label: {
            screenshotLabel(compact: compact).frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
        }
            .disabled(presentation.generatingCapture || presentation.savingScreenshot || !store.category.boardKinds.contains { store.snapshot.boards[$0] != nil })
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

    func renderLeaderboardImage(width: CGFloat = 1000, scheme: ColorScheme = .light, pageRows: Range<Int>? = nil, pageNumber: Int? = nil, pageCount: Int? = nil) -> CGImage? {
        let secondary = scheme == .dark ? Color(red: 0.6, green: 0.6, blue: 0.6) : Color(red: 0.5, green: 0.5, blue: 0.5)
        let content = VStack(alignment: .leading, spacing: 12) {
            HStack {
                appTitle(fontSize: 21)
                Text(tr(store.grouping == .model ? "Models" : "Companies", store.grouping == .model ? "模型" : "公司"))
                Text(LeaderboardPresentation.title(store.category, language: store.language))
                Spacer()
                Text(tr("UPDATED", "更新时间") + " " + LeaderboardPresentation.rankingUpdated(store.snapshot,
                    category: store.category, language: store.language)).font(.caption).foregroundStyle(secondary)
            }
            boardPair(wide: width >= 760, isImage: true, exportScheme: scheme, pageRows: pageRows)
            if store.category == .usage {
                Text(store.category.boardKinds.compactMap { store.snapshot.boards[$0]?.sourceNote }.joined(separator: "\n\n")).font(.system(size: 11)).foregroundStyle(secondary).fixedSize(horizontal: false, vertical: true)
            }
            if store.category.boardKinds.contains(.epochECI) {
                Text(EpochAttribution.fullText(language: store.language))
                    .font(.system(size: 11)).foregroundStyle(secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if store.category.boardKinds.contains(where: { ArenaAttribution.applies(store.snapshot.boards[$0]) }) {
                Text(ArenaAttribution.fullText(language: store.language))
                    .font(.system(size: 11)).foregroundStyle(secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(alignment: .bottom) {
                screenshotDownloadCredit
                Spacer(minLength: 16)
                if let pageNumber, let pageCount { Text("\(pageNumber) / \(pageCount)").monospacedDigit() }
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
    func screenshotPageRanges(pageSize: Int = 24) -> [Range<Int>] {
        let size = max(1, pageSize)
        let count = store.category.boardKinds.map { store.rowPresentation(for: $0).rows.count }.max() ?? 0
        return stride(from: 0, to: max(1, count), by: size).map { $0..<min(count, $0 + size) }
    }
    #if os(iOS)
    private func prepareScreenshotPreview() async {
        guard !presentation.generatingCapture else { return }
        presentation.generatingCapture = true
        presentation.generatedCapturePages = 0
        defer { presentation.generatingCapture = false }
        clearCapturedPages()
        let frozen = LeaderboardPadView(store: LeaderboardPadStore(exporting: store),
            appStoreID: appStoreURL.map { String($0.lastPathComponent.dropFirst(2)) })
        let directory = FileManager.default.temporaryDirectory.appending(path: "benchgauge-export-\(UUID().uuidString)")
        let scheme = colorScheme
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            var paths: [URL] = []
            let ranges = frozen.screenshotPageRanges()
            presentation.totalCapturePages = ranges.count
            for (index, range) in ranges.enumerated() {
                try Task.checkCancellation()
                let png: Data? = autoreleasepool {
                    frozen.renderLeaderboardImage(scheme: scheme, pageRows: range, pageNumber: index + 1, pageCount: ranges.count)
                        .flatMap { UIImage(cgImage: $0).pngData() }
                }
                guard let data = png else { throw CocoaError(.fileWriteUnknown) }
                let path = directory.appending(path: "page-\(index + 1).png")
                try data.write(to: path, options: .atomic)
                paths.append(path)
                presentation.generatedCapturePages = index + 1
                await Task.yield()
            }
            presentation.capturePaths = paths
            presentation.captureIndex = 0
            presentation.savedCapturePages = 0
            presentation.showingCapture = true
        } catch {
            try? FileManager.default.removeItem(at: directory)
            showNote(tr("Could not generate the image. Try again.", "生成图片失败，请重试。"))
        }
    }
    private var screenshotPreview: some View {
        NavigationStack {
            VStack(spacing: 12) {
                if presentation.capturePaths.count > 1 {
                    HStack(spacing: 24) {
                        Button { presentation.captureIndex -= 1 } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
                            .disabled(presentation.captureIndex == 0).accessibilityIdentifier("capture-previous")
                        Text("\(presentation.captureIndex + 1) / \(presentation.capturePaths.count)").monospacedDigit()
                            .accessibilityIdentifier("capture-page-count")
                        Button { presentation.captureIndex += 1 } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }
                            .disabled(presentation.captureIndex + 1 == presentation.capturePaths.count).accessibilityIdentifier("capture-next")
                    }.font(.subheadline)
                }
                ScrollView {
                    if let image = currentCaptureImage {
                        Image(uiImage: image).resizable().scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .accessibilityLabel(tr("Leaderboard image preview", "榜单图片预览"))
                            .accessibilityIdentifier("capture-preview-image")
                    }
                }
                HStack(spacing: 14) {
                    Button {
                        UIPasteboard.general.image = currentCaptureImage
                        #if DEBUG
                        if ProcessInfo.processInfo.arguments.contains("--ui-testing"), ProcessInfo.processInfo.arguments.contains("--export-preview"),
                           let data = currentCaptureImage?.pngData() {
                            let path = URL.documentsDirectory.appending(path: "export-\(store.language.rawValue)-\(colorScheme == .dark ? "dark" : "light").png")
                            try? data.write(to: path)
                        }
                        #endif
                        showNote(tr("Copied to clipboard", "已复制到剪贴板"))
                    } label: { Label(tr("Copy image", "复制图片"), systemImage: "doc.on.doc").frame(maxWidth: .infinity, minHeight: 44) }
                        .buttonStyle(.bordered).accessibilityIdentifier("copy-screenshot")
                    Button { Task { await saveCapturePages() } } label: {
                        Label(presentation.savedCapturePages == presentation.capturePaths.count ? tr("Saved to Photos", "已保存到相册")
                            : presentation.capturePaths.count > 1 ? tr("Save all to Photos", "全部保存到相册") : tr("Save to Photos", "保存到相册"), systemImage: "square.and.arrow.down")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }.buttonStyle(.borderedProminent).accessibilityIdentifier("save-screenshot")
                        .disabled(presentation.savingScreenshot || presentation.savedCapturePages == presentation.capturePaths.count)
                }.font(.subheadline)
            }.padding(16).background(Color.padBackground)
                .navigationTitle(tr("Screenshot", "截图"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button(tr("Done", "完成")) { presentation.showingCapture = false }.disabled(presentation.savingScreenshot) } }
                .overlay(alignment: .bottom) {
                    if let note = presentation.note { Text(note).font(.footnote).padding(12).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8)).padding(.bottom, 80) }
                }
        }.interactiveDismissDisabled(presentation.savingScreenshot)
            .accessibilityIdentifier("capture-preview")
            .alert(tr("Cannot save to Photos", "无法保存到相册"), isPresented: $presentation.photoPermissionDenied) {
                Button(tr("Open Settings", "打开设置")) {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
                Button(tr("Cancel", "取消"), role: .cancel) { }
            } message: {
                Text(tr("Allow adding photos in Settings to save leaderboard images.", "请在系统设置中允许添加照片，以保存榜单图片。"))
            }
    }
    private var currentCaptureImage: UIImage? {
        guard presentation.capturePaths.indices.contains(presentation.captureIndex) else { return nil }
        return UIImage(contentsOfFile: presentation.capturePaths[presentation.captureIndex].path)
    }
    private func clearCapturedPages() {
        guard !presentation.savingScreenshot else { return }
        if let first = presentation.capturePaths.first { try? FileManager.default.removeItem(at: first.deletingLastPathComponent()) }
        presentation.capturePaths = []
        presentation.savedCapturePages = 0
    }
    private func saveCapturePages() async {
        guard !presentation.savingScreenshot else { return }
        presentation.savingScreenshot = true
        defer { presentation.savingScreenshot = false }
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { presentation.photoPermissionDenied = true; return }
        do {
            for path in presentation.capturePaths.dropFirst(presentation.savedCapturePages) {
                guard let image = UIImage(contentsOfFile: path.path) else { throw CocoaError(.fileReadCorruptFile) }
                try await PHPhotoLibrary.shared().performChanges { @Sendable in PHAssetChangeRequest.creationRequestForAsset(from: image) }
                presentation.savedCapturePages += 1
            }
            showNote(tr("Saved to Photos", "已保存到相册"), duration: 4)
        } catch { showNote(tr("Save failed. Try again.", "保存失败，请重试。")) }
    }
    #endif
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
    let countryOptions: [LeaderboardCountryFilter]
    let skeletonHeight: CGFloat
    var failure: LeaderboardFailure? = nil
    @Binding var modelSearchQuery: String
    @Binding var modelSearchPresented: Bool
    @Binding var modelSearchEditing: Bool
    let isRefreshing: Bool
    let polishRevision: Int
    let isImage: Bool
    let compact: Bool
    let denseColumns: Bool
    let exportScheme: ColorScheme?
    let selectCountry: (LeaderboardCountryFilter) -> Void
    let clearFilters: () -> Void
    let selectOpenness: (LeaderboardOpennessFilter) -> Void
    let openModel: (LeaderboardEntry) -> Void
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var searchFocused: Bool
    @State private var searchFocusTask: Task<Void, Never>?
    @State private var headerPinned = false
    @State private var rankingExpanded = false
    @StateObject private var detail = PadBoardDetail()
    private func tr(_ en: String, _ zh: String) -> String { language.text(en, zh) }
    private var rows: [LeaderboardEntry] { rowPresentation.rows }
    private var visibleRowCount: Int { isImage || rankingExpanded ? rows.count : min(20, rows.count) }
    private var displayScheme: ColorScheme { exportScheme ?? colorScheme }
    private var sourceAccent: Color {
        let hex = SourceTabTheme.palette(for: kind, dark: displayScheme == .dark).accent
        let value = UInt32(hex.dropFirst(), radix: 16) ?? 0
        return Color(red: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255)
    }
    private var primaryForeground: Color { isImage ? (displayScheme == .dark ? .white : .black) : .primary }
    private var secondaryForeground: Color {
        guard isImage else { return .secondary }
        let level = displayScheme == .dark ? 0.6 : 0.5
        return Color(red: level, green: level, blue: level)
    }
    private var compactColumns: Bool {
        #if os(iOS)
        !isImage && (compact || denseColumns)
        #else
        false
        #endif
    }
    private var columnSpacing: CGFloat { compactColumns ? 4 : 8 }
    @ScaledMetric(relativeTo: .body) private var opennessIconSize: CGFloat = 14
    @ScaledMetric(relativeTo: .caption2) private var timeFontSize: CGFloat = 11
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
        filterHeader(Text(tr("Country", "国家")), active: filter != .all)
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
    private func filterHeader(_ title: Text, active: Bool) -> some View {
        if isImage {
            title.font(filterHeaderFont)
        } else {
            HStack(spacing: 1) {
                if !active { filterChevron.opacity(0).accessibilityHidden(true) }
                title
                if active {
                    Image(systemName: "line.3.horizontal.decrease")
                        .font(.system(size: (compactColumns ? compactFilterHeaderSize : regularFilterHeaderSize) * 0.75, weight: .semibold))
                        .accessibilityHidden(true)
                } else {
                    filterChevron
                }
            }.font(filterHeaderFont)
                .fontWeight(active ? .semibold : .regular)
                .foregroundStyle(active ? primaryForeground : secondaryForeground)
                .padding(.horizontal, 2).padding(.vertical, 3)
        }
    }
    private var opennessHeaderLabel: some View {
        filterHeader(Text(ModelOpenness.columnTitle(language: language)), active: opennessFilter != .all)
            .accessibilityIdentifier("openness-header-\(kind.rawValue)")
    }
    private func opennessColumn<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ZStack {
            opennessHeaderLabel.hidden()
            ModelOpennessBadge(.closed, language: language, colorScheme: displayScheme,
                showsTitle: !compactColumns, iconSize: opennessIconSize).hidden()
            content()
        }.lineLimit(1).fixedSize(horizontal: true, vertical: false)
    }
    var body: some View {
        Group {
            if isImage { cardContent }
            else { interactiveCard }
        }
        .onChange(of: searchFocused) { _, focused in
            modelSearchEditing = focused
            if !focused { modelSearchPresented = false }
        }
        .onChange(of: isEnabled) { _, enabled in if !enabled { endSearchEditing() } }
        .onChange(of: grouping) { _, _ in endSearchEditing(); rankingExpanded = false }
        .onChange(of: filter) { _, _ in rankingExpanded = false }
        .onChange(of: opennessFilter) { _, _ in rankingExpanded = false }
        .onChange(of: modelSearchQuery) { _, _ in rankingExpanded = false }
        .onDisappear { endSearchEditing() }
    }
    private var searchVisible: Bool { !isImage && grouping == .model && modelSearchPresented }
    // Redistribute the same 12-point inset when pinned, keeping the rows below stationary.
    private var headerTopPadding: CGFloat { headerPinned ? 6 : 4 }
    private var headerBottomPadding: CGFloat { headerPinned ? 6 : 8 }
    private func endSearchEditing() {
        searchFocusTask?.cancel()
        searchFocused = false
        modelSearchPresented = false
    }
    private func openModelSearch() {
        modelSearchPresented = true
        searchFocusTask?.cancel()
        searchFocusTask = Task { @MainActor in
            do { try await Task.sleep(for: .milliseconds(reduceMotion ? 0 : 320)) }
            catch { return }
            guard modelSearchPresented, grouping == .model, isEnabled else { return }
            searchFocused = true
        }
    }
    private func closeModelSearch() {
        endSearchEditing()
        modelSearchPresented = false
        modelSearchQuery = ""
    }
    private var timeLabels: some View {
        let time = LeaderboardPresentation.sourceTime(board, language: language, includesYear: isImage)
        let parts = LeaderboardPresentation.sourceTimeParts(board, language: language, includesYear: isImage)
        let loading = !isImage && isRefreshing
        return HStack(spacing: 0) {
            Text(parts.value)
            if !parts.caption.isEmpty || !isImage {
                Text(" ")
                Group {
                    if parts.caption.isEmpty {
                        Color.clear.frame(width: 12, height: 12)
                    } else {
                        Text(parts.caption).opacity(loading ? 0 : 1)
                    }
                }
                .overlay(alignment: .leading) {
                    if loading {
                        ProgressView().progressViewStyle(.circular).controlSize(.mini)
                            .scaleEffect(0.65).frame(width: 12, height: 12)
                            .tint(secondaryForeground).accessibilityHidden(true)
                    }
                }
            }
        }.font(.system(size: timeFontSize, weight: time.isSourceTime ? .medium : .regular))
        .foregroundStyle(secondaryForeground).monospacedDigit()
        .multilineTextAlignment(.trailing).lineLimit(1).fixedSize()
        .modifier(TimestampPolish(ready: !isImage && !isRefreshing && board != nil && kind != .cloudbaseUsage, revision: polishRevision))
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isStaticText)
        .accessibilityLabel(time.text)
        .accessibilityValue(isRefreshing ? tr("Loading", "加载中") : "")
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
    private var timestamp: some View {
        timeLabels.help(LeaderboardPresentation.sourceTimeHelp(board, language: language))
    }
    @ViewBuilder private var sourceMetadata: some View {
        HStack(alignment: .top, spacing: 12) {
            if isImage {
                sourceDescription
                timeLabels
            } else {
                Button { detail.showingSource = true } label: { sourceDescription }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("source-help-\(kind.rawValue)")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }.font(.caption)
    }
    private var cardMetadata: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isImage {
                Text(LeaderboardPresentation.title(kind, language: language))
                    .font(.subheadline.weight(.medium)).foregroundStyle(primaryForeground)
            }
            sourceMetadata
            if isImage {
                Text(tr("Country", "国家") + ": " + filter.title(language: language) + " · "
                     + ModelOpenness.columnTitle(language: language) + ": " + opennessFilter.title(language: language))
                    .font(.caption).foregroundStyle(secondaryForeground)
            }
        }.padding(.horizontal, columnPadding).padding(.top, 12).padding(.bottom, 6)
    }
    private var sourceHeading: some View {
        Text(kind.sourceLinkTitle)
            .font(columnHeaderFont.weight(.semibold))
            .foregroundStyle(sourceAccent)
            .lineLimit(1).minimumScaleFactor(0.8)
            .accessibilityIdentifier("source-heading-\(kind.rawValue)")
    }
    private var sourceHeadingActions: some View {
        HStack(alignment: .center, spacing: 2) {
            timestamp
            if grouping == .model {
                Button(action: openModelSearch) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12))
                        .frame(width: 28, height: 28).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(sourceAccent)
                .accessibilityLabel(tr("Search models", "搜索模型"))
                .accessibilityIdentifier("model-filter-\(kind.rawValue)")
                .anchorPreference(key: MobileModelSearchOrigin.self, value: .bounds) { $0 }
            }
        }.fixedSize(horizontal: true, vertical: false)
            .layoutPriority(1)
    }
    @ViewBuilder private var sourceHeadingDetails: some View {
        if isImage { sourceHeading }
        else {
            // Dates keep their full width; a long heading takes the remaining
            // space and truncates instead of moving the actions to another row.
            HStack(alignment: .center, spacing: 6) {
                sourceHeading
                sourceHeadingActions
            }
        }
    }
    private var columnHeader: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .leading) {
            HStack(spacing: columnSpacing) {
                Text(tr("Rank", "排名")).lineLimit(1).frame(width: rankColumnWidth)
                HStack(alignment: .center, spacing: 0) {
                    sourceHeadingDetails
                    Spacer(minLength: 0)
                }.frame(maxWidth: .infinity, alignment: .leading)
                if isImage { countryColumn { countryHeaderLabel } }
                else {
                    countryColumn {
                        Menu {
                            Section(tr("Country", "国家")) {
                                ForEach(countryOptions, id: \.self) { option in
                                    Button { selectCountry(option) } label: {
                                        let title = option == .all ? tr("All", "全部") : option.title(language: language)
                                        if option == filter { Label(title, systemImage: "checkmark") }
                                        else { Text(title) }
                                    }
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
                            Section(ModelOpenness.columnTitle(language: language)) {
                                ForEach(LeaderboardOpennessFilter.allCases, id: \.self) { option in
                                    Button { selectOpenness(option) } label: {
                                        let title = option == .all ? tr("All", "全部") : option.title(language: language)
                                        if option == opennessFilter { Label(title, systemImage: "checkmark") }
                                        else { Text(title) }
                                    }.accessibilityIdentifier("openness-option-\(kind.rawValue)-\(option.rawValue)")
                                }
                            }
                        } label: { opennessHeaderLabel }
                        .buttonStyle(.plain).accessibilityIdentifier("openness-filter-\(kind.rawValue)")
                        .accessibilityValue(opennessFilter.title(language: language))
                        .help(ModelOpenness.help(language: language))
                    }
                }
                scoreColumn { Text(LeaderboardPresentation.scoreTitle(kind, language: language)).font(columnHeaderFont) }
            }.font(columnHeaderFont).foregroundStyle(secondaryForeground).padding(.horizontal, columnPadding)
                .padding(.top, headerTopPadding).padding(.bottom, headerBottomPadding)
                .opacity(searchVisible ? 0 : 1)
                .allowsHitTesting(!searchVisible)
                .accessibilityElement(children: .contain)
                .accessibilityHidden(searchVisible)
            }
                .overlayPreferenceValue(MobileModelSearchOrigin.self) { anchor in
                    if let anchor, !isImage && grouping == .model {
                        GeometryReader { geometry in
                            let origin = geometry[anchor]
                            MobileModelSearchBar(query: $modelSearchQuery, focus: $searchFocused,
                                kind: kind, language: language,
                                pinned: headerPinned,
                                close: closeModelSearch)
                                .padding(.top, headerTopPadding).padding(.bottom, headerBottomPadding)
                                .frame(width: searchVisible ? geometry.size.width : origin.width, height: geometry.size.height)
                                .clipped()
                                .offset(x: searchVisible ? 0 : origin.minX)
                                .opacity(searchVisible ? 1 : 0)
                                .allowsHitTesting(searchVisible)
                                .accessibilityHidden(!searchVisible)
                        }
                    }
                }
                .animation(reduceMotion ? nil : .timingCurve(0.4, 0, 0.2, 1, duration: 0.32), value: searchVisible)
            Divider()
        }
        .background(isImage ? (displayScheme == .dark ? Color.black : Color.white) : Color.padCard)
        .id("model-header-\(kind.rawValue)")
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("column-header-\(kind.rawValue)")
        .onGeometryChange(for: Bool.self) { geometry in
            compact && !isImage && geometry.frame(in: .named("rank-scroll-\(kind.rawValue)")).minY <= 0.5
        } action: { headerPinned = $0 }
        .background {
            if compact && !isImage {
                GeometryReader { geometry in
                    let frame = geometry.frame(in: .named("rank-scroll-\(kind.rawValue)"))
                    Color.clear.preference(key: LeaderboardRankFrames.self,
                        value: [-1: LeaderboardRankFrame(minY: frame.minY, maxY: frame.maxY)])
                }
            }
        }
    }
    @ViewBuilder private var cardRows: some View {
        if board != nil {
            if rows.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "chart.bar").font(.title2)
                    Text(tr("No matching entries", "暂无符合条件的模型"))
                    if filter != .all || opennessFilter != .all || grouping == .model && !modelSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Button(tr("Clear filters", "清除筛选"), action: clearFilters)
                            .accessibilityIdentifier("clear-filters-\(kind.rawValue)")
                    }
                }.font(.subheadline).foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 200)
            }
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
                    ForEach(rows.indices.prefix(visibleRowCount).dropFirst(2), id: \.self) { index in
                        rankingRow(rows[index], index: index)
                    }
                }
                if rows.count > 20 {
                    Button { rankingExpanded.toggle() } label: {
                        HStack(spacing: 6) {
                            Text(rankingExpanded ? tr("Show less", "收起")
                                 : tr("Show all \(rows.count)", "展开全部 \(rows.count) 条"))
                            Image(systemName: rankingExpanded ? "chevron.up" : "chevron.down")
                                .font(.caption2)
                        }.font(.subheadline).frame(maxWidth: .infinity).padding(.vertical, 12)
                    }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                    .accessibilityIdentifier("toggle-ranking-\(kind.rawValue)")
                    .accessibilityValue(rankingExpanded ? tr("Expanded", "已展开") : tr("Collapsed", "已收起"))
                }
            }
        } else if isRefreshing && !isImage {
            loadingSkeleton
        } else {
            VStack(spacing: 12) {
                Image(systemName: "chart.bar").font(.title2)
                Text(failure?.message(language: language, hasCachedBoard: false) ?? tr("No shared snapshot yet", "暂未取得共享榜单"))
            }.font(.subheadline).foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 200)
        }
    }
    private var loadingSkeleton: some View {
        VStack(spacing: 0) {
            ForEach(0..<(Int(ceil(max(1, skeletonHeight) / 48)) + 1), id: \.self) { index in
                HStack(spacing: columnSpacing) {
                    Capsule().frame(width: 10, height: 10).frame(width: rankColumnWidth)
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 4).frame(width: 18, height: 18)
                        VStack(alignment: .leading, spacing: 6) {
                            Capsule().frame(maxWidth: index.isMultiple(of: 3) ? 140 : 105).frame(height: 8)
                            Capsule().frame(width: 55, height: 6)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                    countryColumn { RoundedRectangle(cornerRadius: 3).frame(width: 16, height: 12) }
                    opennessColumn { RoundedRectangle(cornerRadius: 3).frame(width: 18, height: 18) }
                    scoreColumn { Capsule().frame(width: 28, height: 8) }
                }
                .foregroundStyle(Color.secondary.opacity(0.13))
                .padding(.horizontal, columnPadding).frame(height: 48)
                .background(index.isMultiple(of: 2) ? Color.clear : Color.secondary.opacity(0.04))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tr("Loading shared rankings…", "正在读取共享榜单…"))
        .accessibilityIdentifier("loading-skeleton-\(kind.rawValue)")
    }
    private var cardContent: some View {
        Group {
            if compact && !isImage {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    cardMetadata
                    Section {
                        if searchVisible || grouping == .model && !modelSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            VStack(spacing: 0) { cardRows }
                                .frame(minHeight: max(0, skeletonHeight - 50), alignment: .top)
                        } else { cardRows }
                    } header: {
                        columnHeader
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    cardMetadata
                    columnHeader
                    cardRows
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
                    if let standing = detail.selectedCompany { Text(CompanyLeaderboard.scoreHelp(for: standing, language: language, kind: kind)).frame(maxWidth: .infinity, alignment: .leading).padding(24) }
                }.navigationTitle(detail.selectedCompany?.entry.name ?? "")
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button(tr("Done", "完成")) { detail.selectedCompany = nil } } }
            }
        }
    }

    private func rankingRow(_ entry: LeaderboardEntry, index: Int) -> some View {
        entryRow(entry, rank: entry.rank).id(PadComparisonScrollTarget.rank(index + 1))
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
            HStack(alignment: .center, spacing: columnSpacing) {
                HStack(spacing: 6) {
                    PadOrganizationLogo(entry: entry, isCompany: grouping == .company)
                    entryName(entry)
                }.padding(.horizontal, 5).padding(.vertical, 3)
                    // Keep the name content and controls at their existing row height.
                    .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
                    .alignmentGuide(.padNameTop) { $0[.top] }
                    .padding(.vertical, 4)
                countryColumn {
                    if let country {
                        countryFlag(country.flagEmoji, title: country.localizedName(language: language), entry: entry)
                    } else {
                        UnknownCountryButton(language: language)
                    }
                }
                opennessColumn {
                    opennessBadge(entry)
                }
                if grouping == .company && !isImage {
                    Button { detail.selectedCompany = LeaderboardPresentation.companies(board, filter: filter, openness: opennessFilter).first { $0.entry.id == entry.id } } label: {
                        scoreColumn { scoreValue(entry) }.frame(height: 44)
                    }.buttonStyle(.plain).foregroundStyle(.secondary)
                    .accessibilityLabel("\(entry.name), \(entry.score), \(tr("score details", "分数说明"))")
                    .accessibilityIdentifier("score-\(kind.rawValue)-\(entry.id)")
                } else {
                    scoreColumn { scoreValue(entry).foregroundStyle(secondaryForeground) }
                }
            }
            .background {
                LeaderboardScoreBackground(color: brandColor(entry).opacity(displayScheme == .dark ? 0.26 : 0.18),
                    score: entry.score, leaderScore: rowPresentation.leaderScore)
                    .padding(.vertical, 4)
            }
        }
        .font(.subheadline).padding(.horizontal, columnPadding).frame(minHeight: 48)
        .background(rank.isMultiple(of: 2) ? Color.secondary.opacity(0.05) : Color.clear)
    }
    @ViewBuilder private func countryFlag(_ flag: String, title: String, entry: LeaderboardEntry) -> some View {
        #if os(iOS)
        if !isImage {
            MobileAttributeHint(title: title, identifier: "country-\(kind.rawValue)-\(entry.id)") {
                Text(flag).foregroundStyle(primaryForeground)
            }
        } else { Text(flag).foregroundStyle(primaryForeground).accessibilityLabel(title) }
        #else
        Text(flag).foregroundStyle(primaryForeground).accessibilityLabel(title)
        #endif
    }
    @ViewBuilder private func opennessBadge(_ entry: LeaderboardEntry) -> some View {
        let identifier = "openness-\(kind.rawValue)-\(entry.id)"
        let badge = ModelOpennessBadge(entry.resolvedOpenness, language: language, colorScheme: displayScheme,
            showsTitle: !compactColumns, accessibilityIdentifier: identifier, iconSize: opennessIconSize)
        #if os(iOS)
        if !isImage && grouping == .model {
            MobileAttributeHint(title: entry.resolvedOpenness?.title(language: language) ?? tr("Unknown", "未知"), identifier: identifier) {
                badge
            }
        } else { badge }
        #else
        badge
        #endif
    }
    private func scoreValue(_ entry: LeaderboardEntry) -> some View {
        Text(LeaderboardPresentation.scoreText(entry.score, kind: kind)).monospacedDigit()
            .overlay(alignment: .bottomTrailing) {
                let share = kind.isShareUsage ? "" : LeaderboardPresentation.scoreShareText(entry.score, leaderScore: rowPresentation.leaderScore)
                if !share.isEmpty {
                    Text(share).font(.system(size: 8)).monospacedDigit()
                        .foregroundStyle(sourceAccent).offset(y: 10)
                        .allowsHitTesting(false)
                }
            }
    }
    @ViewBuilder private func entryName(_ entry: LeaderboardEntry) -> some View {
        if isImage { Text(entry.name).foregroundStyle(primaryForeground).fixedSize(horizontal: false, vertical: true) }
        else if grouping == .company {
            Button {
                detail.selectedCompany = LeaderboardPresentation.companies(board, filter: filter, openness: opennessFilter).first { $0.entry.id == entry.id }
            } label: {
                Text(entry.name).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }.buttonStyle(.plain).accessibilityIdentifier("name-\(kind.rawValue)-\(entry.id)")
        } else {
            #if os(iOS)
            if compactColumns {
                PhoneLeaderboardName(name: entry.name, language: language,
                    identifier: "name-\(kind.rawValue)-\(entry.id)", openDetails: { openModel(entry) })
            } else { copyableEntryName(entry) }
            #else
            copyableEntryName(entry)
            #endif
        }
    }
    private func copyableEntryName(_ entry: LeaderboardEntry) -> some View {
        Button { openModel(entry) } label: {
            Text(entry.name).fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }.buttonStyle(.plain).accessibilityLabel(entry.name + tr(", view model details", "，查看模型详情"))
            .accessibilityIdentifier("name-\(kind.rawValue)-\(entry.id)")
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
                    .frame(width: 20, height: 20)
                    .background(.white)
            }
        }
        .frame(width: 20, height: 20)
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
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

extension Color {
    static var padBackground: Color {
        #if os(iOS)
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 16.0 / 255, green: 18.0 / 255, blue: 22.0 / 255, alpha: 1)
                : UIColor(red: 244.0 / 255, green: 245.0 / 255, blue: 247.0 / 255, alpha: 1)
        })
        #else
        Color(nsColor: .windowBackgroundColor)
        #endif
    }
    static var padCard: Color {
        #if os(iOS)
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(red: 27.0 / 255, green: 31.0 / 255, blue: 38.0 / 255, alpha: 1) : .white
        })
        #else
        padBackground
        #endif
    }
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
