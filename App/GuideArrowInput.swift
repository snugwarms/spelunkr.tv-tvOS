import Combine
import SwiftUI
import UIKit

/// Back must also work during first launch, before a channel row can take focus.
struct GuideBackCapture: UIViewRepresentable {
    var isActive: Bool
    var back: () -> Void
    func makeUIView(context: Context) -> GuideBackCaptureView { GuideBackCaptureView() }
    func updateUIView(_ view: GuideBackCaptureView, context: Context) {
        view.input.isActive = isActive
        view.input.back = back
    }
    static func dismantleUIView(_ view: GuideBackCaptureView, coordinator: ()) { view.detach() }
}

final class GuideBackCaptureView: UIView {
    let input = GuideBackRecognizer()
    private weak var installedWindow: UIWindow?
    init() { super.init(frame: .zero); isUserInteractionEnabled = false; isAccessibilityElement = false }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if installedWindow !== window {
            detach()
            window?.addGestureRecognizer(input)
            installedWindow = window
        }
    }
    func detach() { installedWindow?.removeGestureRecognizer(input); installedWindow = nil }
}

final class GuideBackRecognizer: UIGestureRecognizer, UIGestureRecognizerDelegate {
    var isActive = false
    var back: () -> Void = { }
    init() {
        super.init(target: nil, action: nil)
        allowedPressTypes = [NSNumber(value: UIPress.PressType.menu.rawValue)]
        delegate = self
    }
    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent) {
        state = isActive ? .began : .failed
    }
    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent) {
        guard state == .began else { state = .failed; return }
        state = .ended
        back()
    }
    override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent) { state = .cancelled }
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive press: UIPress) -> Bool { isActive }
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer) -> Bool { true }
}

/// Owns physical arrow presses until key-up, instead of interpreting OS repeat as new taps.
@MainActor
final class GuideArrowInput: ObservableObject {
    var shouldCapture: () -> Bool = { false }
    var move: (MoveCommandDirection) -> Void = { _ in }
    private var heldKey: Int?
    private var repeatTask: Task<Void, Never>?
    private var releasedAt: TimeInterval = -.infinity
    var suppressesMoveCommands: Bool { heldKey != nil || ProcessInfo.processInfo.systemUptime - releasedAt < 0.08 }

    func press(_ key: Int, direction: MoveCommandDirection) {
        guard heldKey != key else { return }
        heldKey = key
        repeatTask?.cancel()
        move(direction)
        repeatTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            while !Task.isCancelled {
                guard let self, heldKey == key else { return }
                move(direction)
                try? await Task.sleep(for: .milliseconds(220))
            }
        }
    }

    func release(_ key: Int? = nil) {
        guard key == nil || key == heldKey else { return }
        heldKey = nil
        repeatTask?.cancel()
        releasedAt = ProcessInfo.processInfo.systemUptime
    }
}

struct GuideArrowCapture: UIViewRepresentable {
    let input: GuideArrowInput
    let shouldCapture: () -> Bool
    let move: (MoveCommandDirection) -> Void
    func makeUIView(context: Context) -> ArrowCaptureView { ArrowCaptureView(input: input) }
    func updateUIView(_ view: ArrowCaptureView, context: Context) {
        input.shouldCapture = shouldCapture
        input.move = move
    }
    static func dismantleUIView(_ view: ArrowCaptureView, coordinator: ()) { view.detach() }
}

final class ArrowCaptureView: UIView {
    private let input: GuideArrowInput
    private let recognizer: ArrowPressRecognizer
    private weak var installedWindow: UIWindow?
    init(input: GuideArrowInput) {
        self.input = input
        recognizer = ArrowPressRecognizer(input: input)
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if installedWindow !== window {
            installedWindow?.removeGestureRecognizer(recognizer)
            window?.addGestureRecognizer(recognizer)
            installedWindow = window
        }
    }
    func detach() {
        input.release()
        installedWindow?.removeGestureRecognizer(recognizer)
        installedWindow = nil
    }
}

final class ArrowPressRecognizer: UIGestureRecognizer, UIGestureRecognizerDelegate {
    private weak var input: GuideArrowInput?
    init(input: GuideArrowInput) {
        self.input = input
        super.init(target: nil, action: nil)
        allowedPressTypes = [UIPress.PressType.upArrow, .downArrow, .leftArrow, .rightArrow].map { NSNumber(value: $0.rawValue) }
        cancelsTouchesInView = true
        delegate = self
    }
    private func direction(_ type: UIPress.PressType) -> MoveCommandDirection? {
        switch type {
        case .upArrow: return .up
        case .downArrow: return .down
        case .leftArrow: return .left
        case .rightArrow: return .right
        default: return nil
        }
    }
    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent) {
        guard let input, input.shouldCapture(), let press = presses.first,
              let direction = direction(press.type) else { state = .failed; return }
        state = state == .possible ? .began : .changed
        input.press(press.type.rawValue, direction: direction)
    }
    override func pressesChanged(_ presses: Set<UIPress>, with event: UIPressesEvent) { }
    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent) {
        for press in presses { input?.release(press.type.rawValue) }
        state = .ended
    }
    override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent) {
        input?.release()
        state = .cancelled
    }
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer) -> Bool { true }
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive press: UIPress) -> Bool { input?.shouldCapture() == true }
}
