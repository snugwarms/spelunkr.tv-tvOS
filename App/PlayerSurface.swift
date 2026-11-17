import AVKit
import Combine
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
    private var socialHost: UIHostingController<VideoOverlays>?
    private var captionObservation: AnyCancellable?
    private struct MenuState: Equatable {
        let canFlipBack: Bool
        let normalizesVolume: Bool
        let captionsEnabled: Bool
        let nativeSubtitles: Bool
        let compatibilityPlayback: Bool
    }
    private var installedMenuState: MenuState?

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
        if self.model !== model {
            self.model = model
            captionObservation = model.captions.$usesNativeSubtitles.combineLatest(model.captions.$isEnabled)
                .receive(on: RunLoop.main)
                .sink { [weak self, weak model] _ in
                    guard let model else { return }
                    self?.updateTransportMenu(model)
                }
        }
        if socialHost == nil, let overlay = controller.contentOverlayView {
            let social = UIHostingController(rootView: VideoOverlays(model: model))
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
        updateTransportMenu(model)
    }

    private func updateTransportMenu(_ model: TVModel) {
        let state = MenuState(canFlipBack: model.canFlipBack, normalizesVolume: model.normalizesVolume,
                              captionsEnabled: model.captions.isEnabled, nativeSubtitles: model.captions.usesNativeSubtitles,
                              compatibilityPlayback: model.usesCompatibilityPlayback)
        guard installedMenuState != state else { return }
        installedMenuState = state
        var items: [UIMenuElement] = [
            UIAction(title: "Rejoin Live", image: UIImage(systemName: "dot.radiowaves.left.and.right")) { [weak model] _ in model?.resumeLive() },
            UIAction(title: "Last Channel", image: UIImage(systemName: "arrow.left.arrow.right"), attributes: model.canFlipBack ? [] : [.disabled]) { [weak model] _ in model?.flipBack() },
            UIAction(title: "Mini Guide", image: UIImage(systemName: "list.bullet")) { [weak model] _ in model?.openMiniGuide() },
            UIAction(title: "Program Guide", image: UIImage(systemName: "rectangle.split.3x3")) { [weak model] _ in model?.openFullGuide() },
            UIAction(title: model.usesCompatibilityPlayback ? "Volume Leveling: Unavailable" : "Volume Leveling", image: UIImage(systemName: "waveform"),
                     attributes: model.usesCompatibilityPlayback ? [.disabled] : [],
                     state: model.normalizesVolume && !model.usesCompatibilityPlayback ? .on : .off) { [weak model] action in
                model?.toggleNormalization()
                action.state = model?.normalizesVolume == true ? .on : .off
            }
        ]
        if !model.captions.usesNativeSubtitles {
            items.append(UIAction(title: model.captions.isEnabled ? model.usesCompatibilityPlayback ? "Subtitles: On (Unavailable)" : "Subtitles: On" : "Subtitles: Off", image: UIImage(systemName: "captions.bubble"),
                      attributes: model.captions.supportedOS ? [] : [.disabled],
                      state: model.captions.isEnabled ? .on : .off) { [weak model] action in
                model?.captions.toggle()
                action.state = model?.captions.isEnabled == true ? .on : .off
            })
        }
        controller.transportBarCustomMenuItems = items
    }

    func playerViewController(_ playerViewController: AVPlayerViewController, didSelect mediaSelectionOption: AVMediaSelectionOption?, in mediaSelectionGroup: AVMediaSelectionGroup) {
        model?.captions.userSelected(mediaSelectionOption, in: mediaSelectionGroup)
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
        model?.userDidNavigatePlayback()
        return CMTime(seconds: plan.clampedSeek(targetTime.seconds, at: Date()), preferredTimescale: 1000)
    }
}

private struct VideoOverlays: View {
    @ObservedObject var model: TVModel
    var body: some View {
        ZStack {
            CommunityOverlay(community: model.community)
            CaptionOverlay(captions: model.captions, community: model.community)
            if let notice = model.compatibilityNotice {
                VStack {
                    Text(notice).font(.system(size: 19, weight: .medium)).multilineTextAlignment(.center)
                        .padding(14).foregroundStyle(.white).background(.black.opacity(0.8), in: RoundedRectangle(cornerRadius: 8))
                        .padding(.horizontal, 30).padding(.top, 30)
                        .accessibilityIdentifier("compatibilityNotice")
                    Spacer()
                }
            }
        }
        .background(Color.clear)
    }
}
