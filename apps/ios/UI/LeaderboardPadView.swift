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
private struct PadFooterTop: PreferenceKey {
    static var defaultValue: CGFloat { .infinity }
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = min(value, nextValue()) }
}
private extension View {
    func trackingFooter(in coordinateSpace: String) -> some View {
        background {
            GeometryReader { geometry in
                Color.clear.preference(key: PadFooterTop.self,
                    value: geometry.frame(in: .named(coordinateSpace)).minY)
            }
        }
    }
}

@MainActor
private final class PadFooterPosition: ObservableObject {
    // Command Line Tools do not ship SwiftUI's @State macro plugin.
    @Published var top: CGFloat = .infinity
}

@MainActor
private struct PadFooterAvoidingControl<Control: View>: ViewModifier {
    let viewportHeight: CGFloat
    let bottomInset: CGFloat
    let trailingInset: CGFloat
    let visible: Bool
    let control: Control
    @StateObject private var footer = PadFooterPosition()

    func body(content: Content) -> some View {
        content
            .onPreferenceChange(PadFooterTop.self) { footer.top = $0 }
            .overlay(alignment: .bottomTrailing) {
                if visible {
                    control.offset(x: -trailingInset,
                        y: -max(bottomInset + 100, viewportHeight - footer.top + 12))
                }
            }
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
    @ScaledMetric(relativeTo: .body) private var englishTitleFontSize: CGFloat = 21
    @StateObject private var presentation = PadPresentationState()
    public static let repositoryURL = URL(string: "https://github.com/cloydlau/ai-benchgauge")!
    private let appStoreURL: URL?

    @StateObject private var cube = LeaderboardCubeState()
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
                    mobileHeader
                    cubeBoards(bottomInset: geometry.safeAreaInsets.bottom)
                }
                .padding(.horizontal, 12).padding(.top, 8)
                .ignoresSafeArea(.container, edges: .bottom)
            } else {
                pairedBoards(bottomInset: geometry.safeAreaInsets.bottom, viewportHeight: geometry.size.height)
            }
        }
        .background { Color.padBackground.ignoresSafeArea() }
        .overlay(alignment: .bottom) {
            MobileCategoryBar(category: $store.category, language: store.language, select: cancelCubeEntrance)
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
        .sheet(isPresented: $presentation.showingAbout) { aboutSheet }
        #if os(iOS)
        .sheet(isPresented: $presentation.showingCapture, onDismiss: clearCapturedPages) { screenshotPreview }
        #endif
        .alert(tr("Feature overview", "功能说明"), isPresented: $presentation.showingQuotaTrackingHelp) {
            Button(tr("Got it", "知道了"), role: .cancel) { }
        } message: {
            Text(AppFeatureCopy.subtitle(language: store.language) + "\n\n" + AppFeatureCopy.quotaMessage(language: store.language))
        }
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

    private var mobileHeader: some View {
        ViewThatFits(in: .horizontal) {
            mobileInlineHeader(titleSize: 30)
            mobileInlineHeader(titleSize: 17)
            mobileInlineHeader(titleSize: 14)
            mobileInlineHeader(titleSize: 11)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func mobileInlineHeader(titleSize: CGFloat) -> some View {
        HStack(spacing: 6) {
            mobileBrandTitle(size: titleSize)
            featureHelp(height: BrandTitleMetrics.inkHeight(language: store.language, fontSize: titleSize)).fixedSize(horizontal: true, vertical: false)
            Spacer(minLength: 0)
            mobileGrouping
        }
    }
    @ViewBuilder private var mobileGrouping: some View {
        #if os(iOS)
        let width: CGFloat = store.language == .english ? 160 : 104
        PadSegmentedControl(values: LeaderboardGrouping.allCases,
            titles: [tr("Models", "模型"), tr("Companies", "公司")], selection: $store.grouping,
            identifier: "grouping", label: tr("Grouping", "分组"), segmentWidth: width / 2, fontSize: 11)
            .frame(width: width, height: 30).id(width)
        #else
        groupingPicker.frame(width: 160)
        #endif
    }
    private func mobileBrandTitle(size: CGFloat) -> some View {
        Group {
                if store.language == .english { appTitle(fontSize: size) }
                else { appTitle.scaleEffect(size / 21, anchor: .leading).padding(.trailing, max(0, (size / 21 - 1) * 65)) }
        }.frame(height: 44)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(store.language.appName)
                .accessibilityAddTraits(.isStaticText)
                .accessibilityIdentifier("brand-title")
    }
    private func featureHelp(height: CGFloat) -> some View {
        Button { presentation.showingQuotaTrackingHelp = true } label: {
            FeatureSubtitle(language: store.language, height: height).foregroundStyle(.secondary)
                .frame(minHeight: 44).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityIdentifier("quota-tracking-help")
            .accessibilityLabel(AppFeatureCopy.subtitle(language: store.language))
    }
    private var aboutSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HStack(alignment: .bottom, spacing: 10) {
                        appTitle
                        Text("v" + (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""))
                            .font(.system(size: 10)).foregroundStyle(.secondary).accessibilityIdentifier("about-version")
                    }.padding(.top, 24)
                    Text(tr("Compare task benchmarks and blind user votes across different AI model capabilities.", "对照任务测评与用户盲测，比较模型在不同场景下的表现。"))
                        .font(.subheadline).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 14) {
                        Text(tr("PC download", "PC 端下载")).font(.subheadline.weight(.semibold))
                        Button(tr("Download the latest desktop version", "下载最新电脑端版本")) {
                            copyName(Self.repositoryURL.appending(path: "releases/latest").absoluteString)
                        }.font(.subheadline).accessibilityIdentifier("desktop-download")
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(18).background(Color.padCard, in: RoundedRectangle(cornerRadius: 12))
                    VStack(alignment: .leading, spacing: 14) {
                        Text(tr("Leaderboard sources", "榜单来源")).font(.subheadline.weight(.semibold))
                        Button("Artificial Analysis") { copyName("https://artificialanalysis.ai/") }
                        Divider()
                        Button("Arena") { copyName("https://arena.ai/leaderboard") }
                    }.font(.subheadline).frame(maxWidth: .infinity, alignment: .leading)
                        .padding(18).background(Color.padCard, in: RoundedRectangle(cornerRadius: 12))
                    VStack(alignment: .leading, spacing: 14) {
                        Text(tr("Open-source notices", "开源声明")).font(.subheadline.weight(.semibold))
                        Text(tr("Third-party software follows its original licenses. Tap to read the full copyright and license text.", "第三方软件分别遵循其原始许可证。点按查看完整版权与许可文本。"))
                            .font(.caption).foregroundStyle(.secondary)
                        DisclosureGroup {
                            Text(BrandFont.licenseText).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                        } label: {
                            HStack {
                                Text(tr("Third-party notice 01", "第三方软件声明 01"))
                                Text("SIL OFL 1.1").font(.caption).foregroundStyle(.secondary)
                            }.font(.subheadline)
                        }.accessibilityIdentifier("open-source-notices")
                    }.padding(18).background(Color.padCard, in: RoundedRectangle(cornerRadius: 12))
                }.padding(20)
            }.background(Color.padBackground)
                .navigationTitle(tr("About", "关于"))
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button(tr("Done", "完成")) { presentation.showingAbout = false } } }
        }
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

    private var cubeSelector: some View {
        HStack(spacing: 6) {
            ForEach(Array(store.category.boardKinds.enumerated()), id: \.offset) { index, kind in
                Button { turnCube(to: index) } label: {
                    Text(kind.sourcePrefix == "Arena" ? tr("User votes", "用户盲测") : tr("Task benchmarks", "任务测评"))
                        .font(.caption.weight(.semibold))
                        .lineLimit(2).frame(maxWidth: .infinity, minHeight: 38)
                        .foregroundStyle(cube.face == index ? (index == 0 ? Color.blue : Color.purple) : Color.secondary)
                        .background(cube.face == index ? (index == 0 ? Color.blue : Color.purple).opacity(0.12) : Color.secondary.opacity(0.06),
                                    in: RoundedRectangle(cornerRadius: 8))
                }.buttonStyle(.plain).accessibilityIdentifier("face-\(index)")
                    .accessibilityAddTraits(cube.face == index ? .isSelected : [])
            }
        }
    }
    private func resetComparison() {
        cancelCubeEntrance()
        cube.rank = nil
        cube.sourceTabsOffset = 0
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
        store.selectedSource = face
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
            .overlay(alignment: .top) {
                cubeSelector.offset(y: -cube.sourceTabsOffset)
                    .allowsHitTesting(cube.sourceTabsOffset < 58)
                    .accessibilityHidden(cube.sourceTabsOffset >= 58)
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
            .simultaneousGesture(DragGesture(minimumDistance: 8)
                .updating($cubeDragAxis) { value, axis, _ in
                    axis = LeaderboardCube.dragAxis(current: axis, x: value.translation.width, y: value.translation.height)
                }
                .onChanged { value in
                    cancelCubeEntrance()
                    guard !cube.turning else { return }
                    guard LeaderboardCube.dragAxis(current: cubeDragAxis, x: value.translation.width, y: value.translation.height) == .horizontal else { return }
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
            .onChange(of: cubeDragAxis) { _, axis in
                // GestureState also resets on cancellation, so the next touch
                // starts fresh and an interrupted turn returns to its face.
                if axis == .undecided && cube.dragging { turnCube(to: cube.face) }
            }
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
                .contentShape(Circle())
                .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tr("Back to top", "返回顶部"))
        .accessibilityIdentifier("leaderboard-back-to-top")
    }

    private func pairedBoards(bottomInset: CGFloat, viewportHeight: CGFloat) -> some View {
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
                    boardPair(wide: true, viewportHeight: viewportHeight)
                    compactFooter.trackingFooter(in: "paired-rankings")
                }
                .padding(18)
                .padding(.bottom, bottomInset + 112)
                .frame(maxWidth: 1100)
                .frame(maxWidth: .infinity)
            }
            .coordinateSpace(name: "paired-rankings")
            .modifier(PadRankingScrollTracking { presentation.pairScrolled = $0 })
            .modifier(PadLeaderboardScrollEdges(edges: .bottom))
            .ignoresSafeArea(.container, edges: .bottom)
            .refreshable { await store.refresh(force: true) }
            .modifier(PadFooterAvoidingControl(viewportHeight: viewportHeight, bottomInset: bottomInset,
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
        return ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Color.clear.frame(height: 48).id(PadComparisonScrollTarget.top)
                    boardCard(kind, compact: true, viewportHeight: size.height)
                        .background {
                            GeometryReader { geometry in
                                let frame = geometry.frame(in: .named("rank-scroll-\(kind.rawValue)"))
                                Color.clear.preference(key: LeaderboardRankFrames.self,
                                    value: [0: LeaderboardRankFrame(minY: frame.minY, maxY: frame.maxY)])
                            }
                        }
                    compactFooter.trackingFooter(in: "rank-scroll-\(kind.rawValue)")
                }
                .padding(.bottom, bottomInset + 112)
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
                        // The pinned header covers part of the scroll viewport.
                        // Compare the first row below it, rather than a hidden row.
                        cube.sourceTabsOffset = min(58, max(0, 58 - (frames[0]?.minY ?? 58)))
                        let heading = frames[-1]
                        cube.columnHeaderHeight = heading.map { $0.maxY - $0.minY } ?? 0
                        let rank = (frames[0]?.minY ?? -.infinity) >= -1 ? 0
                            : LeaderboardCube.visibleRank(frames.filter { $0.key > 0 }, height: size.height,
                                topInset: cube.columnHeaderHeight)
                        if let rank, let row = frames[rank] { cube.comparisonRowHeight = row.maxY - row.minY }
                        if cube.rank != rank { cube.rank = rank }
                    }
                }
                .onChange(of: cube.face) { _, face in
                    if face == index, let rank = cube.rank {
                        // Move the incoming source to the same ranking position
                        // before rotating it into view; never animate the scroll.
                        var transaction = Transaction(); transaction.disablesAnimations = true
                        let target: PadComparisonScrollTarget = rank == 0 ? .top : .rank(rank)
                        let inset = cube.columnHeaderHeight + 4
                        let anchor = rank == 0 ? UnitPoint.top : UnitPoint(x: 0.5,
                            y: min(1, inset / max(1, size.height - cube.comparisonRowHeight)))
                        withTransaction(transaction) { proxy.scrollTo(target, anchor: anchor) }
                    }
                }
                .refreshable { await store.refresh(force: true) }
                .frame(width: size.width, height: size.height)
                .modifier(PadFooterAvoidingControl(viewportHeight: size.height, bottomInset: bottomInset,
                    trailingInset: 12, visible: index == cube.face && (cube.rank ?? 0) > 1,
                    control: rankingBackToTop {
                            withAnimation(usesReducedMotion ? nil : .easeOut(duration: 0.25)) {
                                proxy.scrollTo(PadComparisonScrollTarget.top, anchor: .top)
                            }
                    }))
                .background(Color.padBackground)
                .modifier(CubeFace(position: cube.position, face: index, width: size.width, reduceMotion: usesReducedMotion))
                .allowsHitTesting(index == cube.face && !cube.dragging && !cube.turning)
                .accessibilityHidden(index != cube.face || cube.dragging)
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
            screenshotButton(compact: true).frame(width: 44, height: 44)
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
    private func boardCard(_ kind: LeaderboardKind, isImage: Bool = false, compact: Bool = false, exportScheme: ColorScheme? = nil, viewportHeight: CGFloat = 900, pageRows: Range<Int>? = nil) -> some View {
        PadBoardCard(kind: kind, board: store.snapshot.boards[kind], rowPresentation: pageRows.map { store.rowPresentation(for: kind).page($0) } ?? store.rowPresentation(for: kind), grouping: store.grouping,
            language: store.language, filter: store.countryFilter(for: kind), opennessFilter: store.opennessFilter(for: kind),
            countryOptions: store.availableCountryFilters, skeletonHeight: viewportHeight,
            isRefreshing: store.refreshing.contains(kind), isImage: isImage, compact: compact, exportScheme: exportScheme,
            refresh: { Task { await store.refresh(force: true) } },
            selectCountry: { store.setCountryFilter($0, for: kind); resetComparison() },
            clearFilters: { store.setCountryFilter(.all, for: kind); store.setOpennessFilter(.all, for: kind); resetComparison() },
            selectOpenness: { store.setOpennessFilter($0, for: kind); resetComparison() }, copyName: { name in
                cancelCubeEntrance()
                // A simultaneous cube drag can also release a name button.
                // Only a tap on a settled, stationary board may copy a name.
                guard !compact || (!cube.dragging && !cube.turning) else { return }
                copyName(name)
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
    let isRefreshing: Bool
    let isImage: Bool
    let compact: Bool
    let exportScheme: ColorScheme?
    let refresh: () -> Void
    let selectCountry: (LeaderboardCountryFilter) -> Void
    let clearFilters: () -> Void
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
    @ScaledMetric(relativeTo: .body) private var opennessIconSize: CGFloat = 17
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
        filterHeader(Text(tr("Country", "国家")))
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
        filterHeader(Text(ModelOpenness.columnTitle(language: language)))
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
        if isImage { cardContent }
        else { interactiveCard }
    }
    private var timeLabels: some View {
        Text(LeaderboardPresentation.displayTime(board, language: language))
            .font(.caption2).monospacedDigit().foregroundStyle(secondaryForeground)
            .lineLimit(1).fixedSize().accessibilityIdentifier("source-times-\(kind.rawValue)")
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
        }.padding(.horizontal, columnPadding).padding(.vertical, 12)
    }
    private var columnHeader: some View {
        VStack(spacing: 0) {
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
                            ForEach(countryOptions, id: \.self) { option in
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
        }
        .background(isImage ? (displayScheme == .dark ? Color.black : Color.white) : Color.padCard)
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
                    if filter != .all || opennessFilter != .all {
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
                    ForEach(rows.indices.dropFirst(2), id: \.self) { index in
                        rankingRow(rows[index], index: index)
                    }
                }
            }
        } else if isRefreshing && !isImage {
            loadingSkeleton
        } else {
            VStack(spacing: 12) {
                Image(systemName: "chart.bar").font(.title2)
                Text(tr("No shared snapshot yet", "暂未取得共享榜单"))
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
                        cardRows
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
                    if let standing = detail.selectedCompany { Text(CompanyLeaderboard.scoreHelp(for: standing, language: language)).frame(maxWidth: .infinity, alignment: .leading).padding(24) }
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
            HStack(spacing: 6) {
                PadOrganizationLogo(entry: entry, isCompany: grouping == .company)
                entryName(entry)
            }.padding(.horizontal, 5).padding(.vertical, 3)
                // Fill the 44-point minimum row, leaving 4 points on each side.
                .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
                .background(brandColor(entry).opacity(displayScheme == .dark ? 0.26 : 0.18), in: RoundedRectangle(cornerRadius: 5))
                .alignmentGuide(.padNameTop) { $0[.top] }
                .padding(.vertical, 4)
            countryColumn { Text(country?.flagEmoji ?? "-").foregroundStyle(primaryForeground) }
                .accessibilityLabel(country?.localizedName(language: language) ?? tr("Country unknown", "未知"))
            opennessColumn {
                ModelOpennessBadge(entry.openness, language: language, colorScheme: displayScheme,
                    showsTitle: !compactColumns,
                    accessibilityIdentifier: "openness-\(kind.rawValue)-\(entry.id)", iconSize: opennessIconSize)
            }
            if grouping == .company && !isImage {
                Button { detail.selectedCompany = LeaderboardPresentation.companies(board, filter: filter, openness: opennessFilter).first { $0.entry.id == entry.id } } label: {
                    scoreColumn { Text(entry.score, format: .number.grouping(.never).precision(.fractionLength(1))).monospacedDigit() }.frame(height: 44)
                }.buttonStyle(.plain).foregroundStyle(.secondary)
                .accessibilityLabel("\(entry.name), \(entry.score), \(tr("score details", "分数说明"))")
                .accessibilityIdentifier("score-\(kind.rawValue)-\(entry.id)")
            } else {
                scoreColumn { Text(entry.score, format: .number.grouping(.never).precision(.fractionLength(1))).monospacedDigit().foregroundStyle(secondaryForeground) }
            }
        }
        .font(.subheadline).padding(.horizontal, columnPadding).frame(minHeight: 48)
        .background(rank.isMultiple(of: 2) ? Color.secondary.opacity(0.05) : Color.clear)
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
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 16.0 / 255, green: 21.0 / 255, blue: 28.0 / 255, alpha: 1)
                : UIColor(red: 245.0 / 255, green: 247.0 / 255, blue: 250.0 / 255, alpha: 1)
        })
        #else
        Color(nsColor: .windowBackgroundColor)
        #endif
    }
    static var padCard: Color {
        #if os(iOS)
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(red: 25.0 / 255, green: 33.0 / 255, blue: 44.0 / 255, alpha: 1) : .white
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
