import AVKit
import SwiftUI
import UIKit
import OSLog

/// One embedded AVKit controller is resized between watching, mini guide, and full guide.
struct PlayerSurface: UIViewControllerRepresentable {
    @ObservedObject var model: TVModel
    func makeUIViewController(context: Context) -> PlayerHostController {
        let host = PlayerHostController()
        host.configure(model)
        return host
    }
    func updateUIViewController(_ host: PlayerHostController, context: Context) { host.configure(model) }
}
final class PlayerHostController: UIViewController, AVPlayerViewControllerDelegate {
    private let logger = Logger(subsystem: "tv.spelunkr.community", category: "controls")
    let controller = AVPlayerViewController()
    private weak var model: TVModel?
    private var observation: NSKeyValueObservation?
    private var controlsVisible = false
    private var wasInteractive = false
    private var socialHost: UIHostingController<CommunityOverlay>?
    private var installedLastState: Bool?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        view.accessibilityIdentifier = "videoSurface"
        addChild(controller)
        controller.view.frame = view.bounds
        controller.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(controller.view)
        controller.didMove(toParent: self)
        controller.delegate = self
        controller.videoGravity = .resizeAspect
        controller.allowsPictureInPicturePlayback = false
    }

    func configure(_ model: TVModel) {
        loadViewIfNeeded()
        self.model = model
        if socialHost == nil, let overlay = controller.contentOverlayView {
            let social = UIHostingController(rootView: CommunityOverlay(community: model.community))
            social.view.backgroundColor = .clear
            social.view.isUserInteractionEnabled = false
            addChild(social)
            social.view.frame = overlay.bounds
            social.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            overlay.addSubview(social.view)
            social.didMove(toParent: self)
            socialHost = social
        }
        if controller.player !== model.player {
            controller.player = model.player
            observation = model.player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] player, _ in
                let status = player.timeControlStatus
                Task { @MainActor [weak self] in
                    self?.view.accessibilityValue = status == .playing ? "Playing" : status == .paused ? "Paused" : "Buffering"
                }
            }
        }
        let interactive = model.showsNativeControls && !model.guideVisible
        controller.showsPlaybackControls = interactive
        controller.view.isUserInteractionEnabled = interactive
        view.accessibilityLabel = "Live video: \(model.playback?.plan.program.title ?? "Tuning")"
        if interactive != wasInteractive {
            logger.notice("Native player interactive: \(interactive)")
            wasInteractive = interactive
            setNeedsFocusUpdate()
            updateFocusIfNeeded()
            if interactive {
                DispatchQueue.main.async { [weak self] in
                    guard let self, model.showsNativeControls else { return }
                    UIFocusSystem.focusSystem(for: controller)?.requestFocusUpdate(to: controller)
                    UIFocusSystem.focusSystem(for: controller)?.updateFocusIfNeeded()
                }
            }
        }
        if installedLastState != model.canFlipBack {
            installedLastState = model.canFlipBack
            controller.transportBarCustomMenuItems = [
            UIAction(title: "Rejoin Live", image: UIImage(systemName: "dot.radiowaves.left.and.right")) { [weak model] _ in model?.resumeLive() },
            UIAction(title: "Last Channel", image: UIImage(systemName: "arrow.left.arrow.right"), attributes: model.canFlipBack ? [] : [.disabled]) { [weak model] _ in model?.flipBack() },
            UIAction(title: "Mini Guide", image: UIImage(systemName: "list.bullet")) { [weak model] _ in model?.openMiniGuide() },
            UIAction(title: "Program Guide", image: UIImage(systemName: "rectangle.split.3x3")) { [weak model] _ in model?.openFullGuide() }
            ]
        }
    }

    override var preferredFocusEnvironments: [UIFocusEnvironment] { model?.showsNativeControls == true ? [controller] : [] }
    func playerViewControllerShouldDismiss(_ playerViewController: AVPlayerViewController) -> Bool {
        if model?.showsNativeControls == true { model?.showsNativeControls = false }
        else { model?.openMiniGuide() }
        return false
    }
    func playerViewController(_ playerViewController: AVPlayerViewController, willTransitionToVisibilityOfTransportBar visible: Bool, with coordinator: AVPlayerViewControllerAnimationCoordinator) {
        let wasVisible = controlsVisible
        logger.notice("Transport visible: \(visible), previously: \(wasVisible)")
        controlsVisible = visible
        if wasVisible, !visible, model?.guideVisible == false {
            Task { @MainActor [weak self] in self?.model?.showsNativeControls = false }
        }
    }
    func playerViewController(_ playerViewController: AVPlayerViewController, timeToSeekAfterUserNavigatedFrom oldTime: CMTime, to targetTime: CMTime) -> CMTime {
        guard let plan = model?.playback?.plan else { return targetTime }
        return CMTime(seconds: plan.clampedSeek(targetTime.seconds, at: Date()), preferredTimescale: 1000)
    }
}
