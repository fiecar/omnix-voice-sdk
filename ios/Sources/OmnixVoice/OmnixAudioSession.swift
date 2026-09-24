// Omnix Voice — AVAudioSession management for VoIP (SDK-042).
// Internal to the OmnixVoice module; not part of the public §20A surface.
// Category: playAndRecord, mode: voiceChat.
// Speaker: overrideOutputAudioPort(.speaker) / .none.
// Deactivate with .notifyOthersOnDeactivation on call end.
// Observes AVAudioSession.routeChangeNotification.

import AVFoundation
import Foundation

final class OmnixAudioSession {
    private let session: AVAudioSession
    private var sessionActive = false
    private var speakerEnabled = false
    private var routeObserver: Any?
    private let lock = NSLock()

    /// Fired on the main queue when the resolved output route changes.
    var onRouteChanged: ((OmnixAudioRoute) -> Void)?

    init(session: AVAudioSession = .sharedInstance()) {
        self.session = session
        routeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: session,
            queue: .main
        ) { [weak self] notification in
            self?.handleRouteChange(notification)
        }
    }

    deinit {
        if let routeObserver {
            NotificationCenter.default.removeObserver(routeObserver)
        }
        // Best-effort cleanup; ignore errors during teardown.
        try? endCallAudio()
    }

    var isSessionActive: Bool {
        lock.lock()
        defer { lock.unlock() }
        return sessionActive
    }

    var isSpeakerEnabled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return speakerEnabled
    }

    /// Begin VoIP audio: playAndRecord + voiceChat + activate.
    /// Idempotent while already active (re-applies speaker preference).
    func startCallAudio() throws {
        lock.lock()
        let alreadyActive = sessionActive
        let wantSpeaker = speakerEnabled
        lock.unlock()

        if !alreadyActive {
            try session.setCategory(
                .playAndRecord,
                mode: .voiceChat,
                options: [.allowBluetooth]
            )
            try session.setActive(true)
            lock.lock()
            sessionActive = true
            lock.unlock()
        }
        try applySpeaker(wantSpeaker)
        emitCurrentRoute()
    }

    /// End VoIP audio: clear speaker override, deactivate with
    /// `.notifyOthersOnDeactivation`. Idempotent when inactive.
    func endCallAudio() throws {
        lock.lock()
        let active = sessionActive
        lock.unlock()
        guard active else { return }

        try? session.overrideOutputAudioPort(.none)
        try session.setActive(false, options: .notifyOthersOnDeactivation)

        lock.lock()
        sessionActive = false
        speakerEnabled = false
        lock.unlock()

        emitCurrentRoute()
    }

    /// Update speaker preference. Applied immediately when a call session is
    /// active; otherwise stored for the next `startCallAudio`.
    func setSpeakerEnabled(_ enabled: Bool) throws {
        lock.lock()
        speakerEnabled = enabled
        let active = sessionActive
        lock.unlock()
        if active {
            try applySpeaker(enabled)
            emitCurrentRoute()
        }
    }

    func currentRoute() -> OmnixAudioRoute {
        resolveRoute(from: session.currentRoute)
    }

    private func applySpeaker(_ enabled: Bool) throws {
        try session.overrideOutputAudioPort(enabled ? .speaker : .none)
    }

    private func handleRouteChange(_ notification: Notification) {
        // Reason is informational; we always re-resolve from currentRoute.
        _ = notification.userInfo?[AVAudioSessionRouteChangeReasonKey]
        emitCurrentRoute()
    }

    private func emitCurrentRoute() {
        let route = currentRoute()
        if Thread.isMainThread {
            onRouteChanged?(route)
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.onRouteChanged?(route)
            }
        }
    }

    private func resolveRoute(from route: AVAudioSessionRouteDescription) -> OmnixAudioRoute {
        let outputs = route.outputs
        if outputs.contains(where: {
            $0.portType == .bluetoothHFP
                || $0.portType == .bluetoothA2DP
                || $0.portType == .bluetoothLE
        }) {
            return .BLUETOOTH
        }
        if outputs.contains(where: {
            $0.portType == .headphones || $0.portType == .headsetMic
        }) {
            return .WIRED_HEADSET
        }
        if outputs.contains(where: { $0.portType == .builtInSpeaker }) {
            return .SPEAKER
        }
        if outputs.contains(where: { $0.portType == .builtInReceiver }) {
            return .EARPIECE
        }
        return outputs.isEmpty ? .UNKNOWN : .UNKNOWN
    }
}
