import SwiftUI

enum MobilePullRefreshPolicy {
    static func shouldRefresh(startedAtTop: Bool, translation: CGSize) -> Bool {
        startedAtTop && translation.height >= 64 && translation.height > abs(translation.width) * 1.2
    }
}

@MainActor
struct MobilePullRefreshContent: ViewModifier {
    var enabled: Bool = true
    var topSpacer: CGFloat = 0
    let identifier: String
    let loadingLabel: String
    let action: @MainActor () async -> Void
    @State private var refreshing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @ViewBuilder func body(content: Content) -> some View {
        #if os(iOS)
        content.padding(.top, refreshing ? 55 : 0)
            .background {
                MobilePullRefresh(enabled: enabled, topSpacer: topSpacer,
                    identifier: identifier, loadingLabel: loadingLabel, onRefreshing: { visible in
                        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { refreshing = visible }
                    }, action: action)
            }
        #else
        content.refreshable { await action() }
        #endif
    }
}

#if os(iOS)
import UIKit

/// Binds inside one board's scroll content, without replacing its scroll delegate.
@MainActor
struct MobilePullRefresh: UIViewRepresentable {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var enabled: Bool = true
    var topSpacer: CGFloat = 0
    let identifier: String
    let loadingLabel: String
    let onRefreshing: @MainActor (Bool) -> Void
    let action: @MainActor () async -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> Probe {
        let view = Probe()
        view.isUserInteractionEnabled = false
        view.attach = { [weak coordinator = context.coordinator] in coordinator?.attach(from: $0) }
        updateUIView(view, context: context)
        return view
    }
    func updateUIView(_ view: Probe, context: Context) {
        if let previous = context.coordinator.owner, previous.identifier != identifier {
            context.coordinator.detach()
        }
        context.coordinator.owner = self
        view.attach?(view)
    }
    static func dismantleUIView(_ view: Probe, coordinator: Coordinator) { coordinator.detach() }

    final class Probe: UIView {
        var attach: ((UIView) -> Void)?
        override func didMoveToWindow() { super.didMoveToWindow(); attach?(self) }
        override func layoutSubviews() { super.layoutSubviews(); attach?(self) }
    }
    @MainActor final class Coordinator: NSObject {
        var owner: MobilePullRefresh?
        weak var scroll: UIScrollView?
        let dots = Dots()
        var startedAtTop = false
        var task: Task<Void, Never>?
        func attach(from view: UIView) {
            var parent = view.superview
            while let current = parent, !(current is UIScrollView) { parent = current.superview }
            guard let found = parent as? UIScrollView, let owner else { return }
            if scroll !== found {
                detach(); scroll = found
                found.alwaysBounceVertical = true
                found.panGestureRecognizer.addTarget(self, action: #selector(pan(_:)))
                found.addSubview(dots)
            }
            dots.accessibilityIdentifier = owner.identifier
            dots.accessibilityLabel = owner.loadingLabel
            dots.frame = CGRect(x: 0, y: owner.topSpacer - (task == nil ? 55 : 0), width: found.bounds.width, height: 55)
            dots.autoresizingMask = [.flexibleWidth]
        }
        @objc func pan(_ gesture: UIPanGestureRecognizer) {
            guard let scroll, let owner, task == nil else { return }
            let translation = gesture.translation(in: scroll)
            switch gesture.state {
            case .began:
                startedAtTop = owner.enabled && scroll.contentOffset.y <= -scroll.adjustedContentInset.top + 1
            case .changed:
                dots.show(startedAtTop && owner.enabled && translation.y > 8 && translation.y > abs(translation.x) * 1.2, animated: false)
            case .ended:
                let ready = owner.enabled && MobilePullRefreshPolicy.shouldRefresh(startedAtTop: startedAtTop,
                    translation: CGSize(width: translation.x, height: translation.y))
                startedAtTop = false
                guard ready else { dots.show(false, animated: false); return }
                beginRefresh()
            case .cancelled, .failed:
                startedAtTop = false; dots.show(false, animated: false)
            default: break
            }
        }
        func beginRefresh() {
            guard task == nil, scroll != nil, let owner else { return }
            owner.onRefreshing(true)
            dots.frame.origin.y = owner.topSpacer
            dots.show(true, animated: !owner.reduceMotion)
            task = Task { [weak self] in
                await owner.action()
                guard let self, !Task.isCancelled else { return }
                self.finish()
            }
        }
        func finish() {
            dots.show(false, animated: false)
            owner?.onRefreshing(false)
            task = nil
        }
        func detach() {
            if task != nil, let end = owner?.onRefreshing {
                DispatchQueue.main.async { end(false) }
            }
            task?.cancel(); task = nil
            scroll?.panGestureRecognizer.removeTarget(self, action: #selector(pan(_:)))
            startedAtTop = false
            dots.show(false, animated: false); dots.removeFromSuperview(); scroll = nil
        }
    }
    final class Dots: UIView {
        private let circles = (0..<3).map { _ in UIView() }
        override init(frame: CGRect) {
            super.init(frame: frame)
            isHidden = true; isUserInteractionEnabled = false; isAccessibilityElement = true
            for circle in circles { circle.backgroundColor = .secondaryLabel; circle.layer.cornerRadius = 2.5; addSubview(circle) }
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override func layoutSubviews() {
            super.layoutSubviews()
            for (index, circle) in circles.enumerated() {
                circle.frame = CGRect(x: bounds.midX - 13.5 + CGFloat(index) * 11, y: bounds.midY - 2.5, width: 5, height: 5)
            }
        }
        func show(_ visible: Bool, animated: Bool) {
            isHidden = !visible
            for (index, circle) in circles.enumerated() {
                circle.layer.removeAnimation(forKey: "pulse")
                guard visible && animated && !UIAccessibility.isReduceMotionEnabled else { continue }
                let animation = CAKeyframeAnimation(keyPath: "opacity")
                animation.values = [0.35, 1, 0.35]; animation.keyTimes = [0, 0.5, 1]
                animation.duration = 0.9; animation.repeatCount = .infinity
                animation.beginTime = CACurrentMediaTime() + Double(index) * 0.15
                circle.layer.add(animation, forKey: "pulse")
            }
        }
    }
}
#endif
