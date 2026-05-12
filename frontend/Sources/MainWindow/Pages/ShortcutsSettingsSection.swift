import SwiftUI

struct ShortcutsSettingsSection: View {
    @ObservedObject private var settings = ShortcutSettings.shared
    @Binding var highlightedSettingId: String?

    @State private var isRecordingAskOmi = false
    @State private var askOmiEventMonitor: Any?
    @State private var isRecordingPTT = false
    @State private var pttEventMonitor: Any?

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Shortcuts")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.white)

            // MARK: Ask Omi
            shortcutCard(settingId: "shortcuts.askomi") {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Hotkey de activación (Ask Omi)")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)
                        Text("Pulsa el hotkey para abrir el floating bar e iniciar el dictado de voz.")
                            .font(.system(size: 12))
                            .foregroundColor(OmiColors.textTertiary)
                    }

                    Toggle("Activado", isOn: $settings.askOmiEnabled)
                        .font(.system(size: 13)).foregroundColor(.white).toggleStyle(.switch)

                    HStack(spacing: 8) {
                        ForEach(ShortcutSettings.askOmiPresets, id: \.self) { preset in
                            HotkeyChip(
                                label: preset.displayLabel,
                                isSelected: !isRecordingAskOmi && settings.askOmiShortcut == preset
                            ) {
                                stopRecordingAskOmi()
                                settings.askOmiShortcut = preset
                            }
                        }
                    }

                    HStack(spacing: 12) {
                        Button {
                            isRecordingAskOmi ? stopRecordingAskOmi() : startRecordingAskOmi()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: isRecordingAskOmi ? "record.circle.fill" : "keyboard")
                                    .font(.system(size: 12))
                                Text(isRecordingAskOmi ? "Presiona la combinación…" : "Shortcut personalizado")
                                    .font(.system(size: 12))
                            }
                            .foregroundColor(isRecordingAskOmi ? .red : OmiColors.textTertiary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(isRecordingAskOmi ? Color.red.opacity(0.1) : Color.white.opacity(0.06))
                            .cornerRadius(7)
                            .overlay(
                                RoundedRectangle(cornerRadius: 7)
                                    .stroke(isRecordingAskOmi ? Color.red.opacity(0.4) : Color.white.opacity(0.1), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)

                        if isRecordingAskOmi {
                            Text("Esc para cancelar")
                                .font(.system(size: 11))
                                .foregroundColor(OmiColors.textQuaternary)
                        } else if !ShortcutSettings.askOmiPresets.contains(settings.askOmiShortcut) {
                            HotkeyChip(label: settings.askOmiShortcut.displayLabel, isSelected: true) {}
                        }
                    }
                }
            }

            // MARK: Push to Talk
            shortcutCard(settingId: "shortcuts.ptt") {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Push to Talk")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)
                        Text("Mantén pulsado para grabar voz; suelta para enviar.")
                            .font(.system(size: 12))
                            .foregroundColor(OmiColors.textTertiary)
                    }

                    Toggle("Activado", isOn: $settings.pttEnabled)
                        .font(.system(size: 13)).foregroundColor(.white).toggleStyle(.switch)

                    HStack(spacing: 8) {
                        ForEach(ShortcutSettings.pttPresets, id: \.self) { preset in
                            HotkeyChip(
                                label: preset.displayLabel,
                                isSelected: !isRecordingPTT && settings.pttShortcut == preset
                            ) {
                                stopRecordingPTT()
                                settings.pttShortcut = preset
                            }
                        }
                    }

                    HStack(spacing: 12) {
                        Button {
                            isRecordingPTT ? stopRecordingPTT() : startRecordingPTT()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: isRecordingPTT ? "record.circle.fill" : "keyboard")
                                    .font(.system(size: 12))
                                Text(isRecordingPTT ? "Presiona modificador…" : "Shortcut personalizado")
                                    .font(.system(size: 12))
                            }
                            .foregroundColor(isRecordingPTT ? .red : OmiColors.textTertiary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(isRecordingPTT ? Color.red.opacity(0.1) : Color.white.opacity(0.06))
                            .cornerRadius(7)
                            .overlay(
                                RoundedRectangle(cornerRadius: 7)
                                    .stroke(isRecordingPTT ? Color.red.opacity(0.4) : Color.white.opacity(0.1), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)

                        if isRecordingPTT {
                            Text("Esc para cancelar")
                                .font(.system(size: 11))
                                .foregroundColor(OmiColors.textQuaternary)
                        } else if !ShortcutSettings.pttPresets.contains(settings.pttShortcut) {
                            HotkeyChip(label: settings.pttShortcut.displayLabel, isSelected: true) {}
                        }
                    }

                    Toggle("Doble pulsación para bloquear", isOn: $settings.doubleTapForLock)
                        .font(.system(size: 13)).foregroundColor(.white).toggleStyle(.switch)
                }
            }

            // MARK: Misc
            shortcutCard(settingId: "shortcuts.misc") {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Floating bar arrastrable", isOn: $settings.draggableBarEnabled)
                        .font(.system(size: 13)).foregroundColor(.white).toggleStyle(.switch)
                    Toggle("Sonidos al activar / detener", isOn: $settings.pttSoundsEnabled)
                        .font(.system(size: 13)).foregroundColor(.white).toggleStyle(.switch)
                }
            }
        }
        .onDisappear {
            stopRecordingAskOmi()
            stopRecordingPTT()
        }
    }

    // MARK: - Recording helpers

    private func startRecordingAskOmi() {
        isRecordingAskOmi = true
        askOmiEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            if event.keyCode == 53 {
                DispatchQueue.main.async { self.stopRecordingAskOmi() }
                return nil
            }
            if let shortcut = ShortcutSettings.KeyboardShortcut.fromRecordingEvent(event, allowModifierOnly: false),
               shortcut.supportsGlobalHotKey {
                DispatchQueue.main.async {
                    self.settings.askOmiShortcut = shortcut
                    self.stopRecordingAskOmi()
                }
                return nil
            }
            return event
        }
    }

    private func stopRecordingAskOmi() {
        isRecordingAskOmi = false
        if let monitor = askOmiEventMonitor {
            NSEvent.removeMonitor(monitor)
            askOmiEventMonitor = nil
        }
    }

    private func startRecordingPTT() {
        isRecordingPTT = true
        pttEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged]) { event in
            if event.keyCode == 53 {
                DispatchQueue.main.async { self.stopRecordingPTT() }
                return nil
            }
            if let shortcut = ShortcutSettings.KeyboardShortcut.fromRecordingEvent(event, allowModifierOnly: true) {
                DispatchQueue.main.async {
                    self.settings.pttShortcut = shortcut
                    self.stopRecordingPTT()
                }
                return nil
            }
            return event
        }
    }

    private func stopRecordingPTT() {
        isRecordingPTT = false
        if let monitor = pttEventMonitor {
            NSEvent.removeMonitor(monitor)
            pttEventMonitor = nil
        }
    }

    // MARK: - UI helpers

    private func shortcutCard<Content: View>(settingId: String, @ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(16)
            .background(OmiColors.backgroundSecondary)
            .cornerRadius(10)
            .id(settingId)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(highlightedSettingId == settingId ? OmiColors.purplePrimary : Color.clear, lineWidth: 2)
            )
    }
}
