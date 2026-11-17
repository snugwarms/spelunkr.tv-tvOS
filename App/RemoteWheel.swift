import Combine
import GameController
import SpelunkrCore

@MainActor
final class RemoteWheel: ObservableObject {
    let steps = PassthroughSubject<Int, Never>()
    private var wheel = ClickWheel()
    private var connection: NSObjectProtocol?
    private var configured: Set<ObjectIdentifier> = []

    init() {
        connection = NotificationCenter.default.addObserver(forName: .GCControllerDidConnect, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.connect() }
        }
        connect()
    }

    private func connect() {
        for controller in GCController.controllers() {
            guard let pad = controller.microGamepad, pad.dpad.isAnalog, !configured.contains(ObjectIdentifier(controller)) else { continue }
            configured.insert(ObjectIdentifier(controller))
            pad.reportsAbsoluteDpadValues = true
            pad.dpad.valueChangedHandler = { [weak self] _, x, y in
                let timestamp = ProcessInfo.processInfo.systemUptime
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    let value = wheel.update(x: Double(x), y: Double(y), timestamp: timestamp)
                    if value != 0 { steps.send(value) }
                }
            }
        }
    }
}
