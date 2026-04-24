import AVFoundation
import Cocoa
import Combine

/// Push-to-talk manager for voice input.
///
/// State machine:
///   idle → [hotkey/shortcut down] → listening → [hotkey/shortcut up or tap] → finalizing → sends query → idle
///   idle → [quick tap] → pendingLockDecision → [tap again within 400ms] → lockedListening
///   pendingLockDecision → [timeout] → finalizing → sends query → idle
///
/// STT: Parakeet v3 0.6B ONNX via ParakeetSTTService.
@MainActor
class PushToTalkManager: ObservableObject {
    static let shared = PushToTalkManager()

    enum PTTState { case idle, listening, pendingLockDecision, lockedListening, finalizing }

    @Published private(set) var state: PTTState = .idle

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var barState: FloatingControlBarState?

    private var lastOptionDownTime: TimeInterval = 0
    private var lastOptionUpTime: TimeInterval = 0
    private let doubleTapThreshold: TimeInterval = 0.4
    private let tapToLockMaxHoldDuration: TimeInterval = 0.22
    private var finalizeWorkItem: DispatchWorkItem?
    private var isCurrentSessionFollowUp = false

    // MARK: - STT (Parakeet v3 0.6B ONNX via ParakeetSTTService)

    private init() {}

    func setup(barState: FloatingControlBarState) {
        self.barState = barState
        installEventMonitors()
        log("PushToTalkManager: setup complete")
    }

    func cleanup() {
        stopSTT()
        state = .idle
        removeEventMonitors()
        log("PushToTalkManager: cleanup complete")
    }

    // MARK: - Event Monitors

    private func installEventMonitors() {
        removeEventMonitors()
        let monitorMask: NSEvent.EventTypeMask = [.flagsChanged, .keyDown, .keyUp]

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: monitorMask) { [weak self] event in
            Task { @MainActor in self?.handleShortcutEvent(event) }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: monitorMask) { [weak self] event in
            Task { @MainActor in self?.handleShortcutEvent(event) }
            return event
        }
    }

    private func removeEventMonitors() {
        if let m = globalMonitor { NSEvent.removeMonitor(m); globalMonitor = nil }
        if let m = localMonitor { NSEvent.removeMonitor(m); localMonitor = nil }
    }

    // MARK: - Shortcut Handling (modifier-only PTT keys)

    private func handleShortcutEvent(_ event: NSEvent) {
        guard ShortcutSettings.shared.pttEnabled else { return }
        let shortcut = ShortcutSettings.shared.pttShortcut

        let pttActive: Bool
        switch event.type {
        case .flagsChanged:
            guard shortcut.modifierOnly else { return }
            pttActive = shortcut.matchesFlagsChanged(event)
        case .keyDown:
            guard !shortcut.modifierOnly, !event.isARepeat else { return }
            pttActive = shortcut.matchesKeyDown(event)
        case .keyUp:
            guard !shortcut.modifierOnly else { return }
            if shortcut.matchesKeyUp(event) { handleShortcutUp() }
            return
        default:
            return
        }

        if pttActive, !FloatingControlBarManager.shared.isVisible {
            FloatingControlBarManager.shared.show()
        }
        guard FloatingControlBarManager.shared.isVisible else { return }

        if pttActive {
            handleShortcutDown()
        } else if shortcut.modifierOnly {
            handleShortcutUp()
        }
    }

    private func handleShortcutDown() {
        let now = ProcessInfo.processInfo.systemUptime
        switch state {
        case .idle:
            if ShortcutSettings.shared.doubleTapForLock && (now - lastOptionUpTime) < doubleTapThreshold {
                lastOptionUpTime = 0
                enterLockedListening()
            } else {
                lastOptionDownTime = now
                startListening()
            }
        case .listening:
            break
        case .pendingLockDecision:
            state = .lockedListening
            updateBarState()
        case .lockedListening:
            finalize()
        case .finalizing:
            break
        }
    }

    private func handleShortcutUp() {
        let now = ProcessInfo.processInfo.systemUptime
        switch state {
        case .listening:
            let holdDuration = now - lastOptionDownTime
            if ShortcutSettings.shared.doubleTapForLock && holdDuration < tapToLockMaxHoldDuration {
                lastOptionUpTime = now
                enterPendingLockDecision()
            } else {
                lastOptionUpTime = 0
                finalize()
            }
        default:
            break
        }
    }

    // MARK: - Hotkey-triggered toggle (Carbon global hotkey → any key combo)

    /// Called by the Carbon global hotkey — toggles locked-listening mode on/off.
    func handleHotkeyTap() {
        switch state {
        case .idle:
            if !FloatingControlBarManager.shared.isVisible {
                FloatingControlBarManager.shared.show()
            }
            enterLockedListening()
        case .listening, .lockedListening, .pendingLockDecision:
            finalize()
        case .finalizing:
            break
        }
    }

    // MARK: - Listening Lifecycle

    private func startListening() {
        FloatingBarVoicePlaybackService.shared.interruptCurrentResponse()
        state = .listening
        isCurrentSessionFollowUp = barState?.showingAIResponse == true
        finalizeWorkItem?.cancel()
        finalizeWorkItem = nil

        if ShortcutSettings.shared.pttSoundsEnabled {
            let sound = NSSound(named: "Funk")
            sound?.volume = 0.3
            sound?.play()
        }

        updateBarState()
        beginSTT()
        log("PushToTalkManager: started listening")
    }

    private func enterLockedListening() {
        FloatingBarVoicePlaybackService.shared.interruptCurrentResponse()
        finalizeWorkItem?.cancel()
        finalizeWorkItem = nil
        state = .lockedListening
        isCurrentSessionFollowUp = barState?.showingAIResponse == true
        updateBarState()
        beginSTT()
        log("PushToTalkManager: entered locked listening")
    }

    private func enterPendingLockDecision() {
        guard state == .listening else { return }
        state = .pendingLockDecision
        updateBarState()

        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                guard let self, self.state == .pendingLockDecision else { return }
                self.finalize()
            }
        }
        finalizeWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + doubleTapThreshold, execute: workItem)
    }

    func cancelListening() {
        guard state != .idle else { return }
        log("PushToTalkManager: cancelling listening")
        Task { await ParakeetSTTService.shared.stop() }
        state = .idle
        finalizeWorkItem?.cancel()
        finalizeWorkItem = nil
        isCurrentSessionFollowUp = false
        updateBarState()
    }

    private func finalize() {
        guard state == .listening || state == .lockedListening || state == .pendingLockDecision else { return }
        let wasFollowUp = isCurrentSessionFollowUp

        state = .finalizing
        finalizeWorkItem?.cancel()
        finalizeWorkItem = nil

        if ShortcutSettings.shared.pttSoundsEnabled {
            let sound = NSSound(named: "Bottle")
            sound?.volume = 0.3
            sound?.play()
        }

        isCurrentSessionFollowUp = false
        updateBarState(skipResize: wasFollowUp)

        Task { @MainActor in
            let transcript = await ParakeetSTTService.shared.stop()
            guard self.state == .finalizing else { return }
            self.state = .idle
            self.updateBarState(skipResize: wasFollowUp)
            if !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                log("PushToTalkManager: sending transcript '\(transcript)'")
                FloatingControlBarManager.shared.openAIInputWithQuery(transcript, fromVoice: true)
            } else {
                FloatingControlBarManager.shared.openAIInput()
            }
        }
    }

    // MARK: - STT

    private func beginSTT() {
        Task { @MainActor in
            await ParakeetSTTService.shared.start(
                updateHandler: { [weak self] partial in
                    self?.barState?.voiceTranscript = partial
                },
                levelCallback: { [weak self] level in
                    self?.barState?.micLevel = level
                }
            )
        }
    }

    @discardableResult
    private func stopSTT() -> String {
        // Synchronous wrapper — actual async transcript fetched in finalize()
        return ""
    }

    // MARK: - Bar State Sync

    private func updateBarState(skipResize: Bool = false) {
        guard let barState = barState else { return }
        let wasListening = barState.isVoiceListening
        let isShowingVoiceUI = (state == .listening || state == .lockedListening)
        barState.isVoiceListening = isShowingVoiceUI
        barState.isVoiceLocked = (state == .lockedListening)
        barState.isVoiceFollowUp = isCurrentSessionFollowUp && isShowingVoiceUI
        if !isShowingVoiceUI {
            barState.voiceTranscript = ""
            barState.voiceFollowUpTranscript = ""
        }

        let isOnboarding = !UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
        guard !skipResize && !barState.isVoiceFollowUp && !barState.showingAIConversation && !isOnboarding else { return }
        if barState.isVoiceListening && !wasListening {
            FloatingControlBarManager.shared.resizeForPTT(expanded: true)
        } else if !barState.isVoiceListening && wasListening {
            FloatingControlBarManager.shared.resizeForPTT(expanded: false)
        }
    }
}
