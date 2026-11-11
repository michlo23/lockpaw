import SwiftUI
import ServiceManagement
import Carbon

/// General: the shortcut and how unlocking works, what happens while locked, how Lockpaw
/// starts, and the one permission it needs. A missing permission moves to the top.
struct GeneralSettingsPane: View {
    @AppStorage("hotkeyEnabled") private var hotkeyEnabled = HotkeyConfig.defaultEnabled
    @AppStorage(HotkeyConfig.requireAuthenticationToUnlockKey) private var requiresAuthentication = HotkeyConfig.defaultRequireAuthenticationToUnlock
    @AppStorage(Constants.sleepWhenAgentFinishesKey) private var sleepShortcut = false
    @AppStorage("hotkeyDisplay") private var hotkeyDisplay = HotkeyConfig.defaultDisplay // redraws the sleep shortcut
    @AppStorage(Constants.lidClosedModeKey) private var lidClosedMode = false
    @AppStorage(Constants.unlockWithMacKey) private var unlockWithMac = false
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage(Constants.showMenuBarIconKey) private var showMenuBarIcon = true

    @ObservedObject private var lidSleep = LidSleepController.shared
    @State private var accessibilityGranted = AccessibilityChecker.isEnabled

    /// Accessibility can be granted in System Settings at any moment; poll while visible.
    private let accessibilityPoll = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            if !accessibilityGranted { permissionSection }

            Section("Shortcut") {
                Toggle(isOn: $hotkeyEnabled) {
                    SettingLabel("Lock and unlock with a shortcut", detail: "Works from any app.")
                }
                .onChange(of: hotkeyEnabled) { _, enabled in
                    NotificationCenter.default.post(
                        name: .lockpawHotkeyPreferenceChanged, object: nil, userInfo: ["enabled": enabled]
                    )
                }

                if hotkeyEnabled {
                    LabeledContent("Shortcut") { HotkeyRecorder() }

                    Toggle(isOn: $sleepShortcut) {
                        SettingLabel(
                            "Lock & sleep: \(HotkeyConfig.sleepDisplay ?? "unavailable")",
                            detail: "Locks too, and once every agent is done it locks macOS and puts the Mac to sleep. \(hotkeyDisplay) alone never sleeps."
                        )
                    }
                    .onChange(of: sleepShortcut) {
                        NotificationCenter.default.post(name: .lockpawHotkeyPreferenceChanged, object: nil)
                    }

                    Toggle(isOn: $requiresAuthentication) {
                        SettingLabel("Ask for Touch ID to unlock", detail: "The shortcut only unlocks after Touch ID or your password.")
                    }
                }
            }

            Section("While locked") {
                Toggle(isOn: Binding(get: { lidClosedMode }, set: { lidSleep.setEnabled($0) })) {
                    SettingLabel(
                        "Keep running with the lid closed",
                        detail: "Your agents keep working. Sleep comes back if the Mac runs hot or the battery drops to \(LidSleepPolicy.batteryFloor)%."
                    )
                }

                if lidClosedMode {
                    LabeledContent {
                        lidHelperControl
                    } label: {
                        SettingLabel("Helper", detail: lidSleep.lastError ?? lidHelperDetail)
                    }
                }

                Toggle(isOn: $unlockWithMac) {
                    SettingLabel("Unlock with your Mac", detail: "When macOS locks too, unlocking your Mac also unlocks Lockpaw.")
                }
            }

            Section("Lockpaw") {
                Toggle("Open at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        do {
                            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                        } catch {
                            launchAtLogin = !enabled
                        }
                    }

                Toggle(isOn: $showMenuBarIcon) {
                    SettingLabel(
                        "Show in menu bar",
                        detail: showMenuBarIcon ? nil : "Hidden. Open Lockpaw from Applications to get the icon and this window back."
                    )
                }
            }

            if accessibilityGranted { permissionSection }
        }
        .settingsPane(.general)
        .onReceive(accessibilityPoll) { _ in
            let granted = AccessibilityChecker.isEnabled
            if granted != accessibilityGranted { accessibilityGranted = granted }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            // The user may be back from approving the helper in Login Items.
            lidSleep.refreshStatus()
        }
    }

    private var permissionSection: some View {
        Section("Permissions") {
            LabeledContent {
                if accessibilityGranted {
                    Label("Allowed", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(settingsAccentColor)
                } else {
                    Button("Open System Settings") { AccessibilityChecker.openSystemSettings() }
                }
            } label: {
                SettingLabel(
                    "Accessibility",
                    detail: accessibilityGranted ? nil : "Needed for the shortcut and to block the keyboard while locked."
                )
            }
        }
    }

    private var lidHelperDetail: String {
        switch lidSleep.helperStatus {
        case .enabled: return lidSleep.sleepHeld ? "Keeping the Mac awake while locked." : "Ready. Only active while Lockpaw is locked."
        case .requiresApproval: return "Allow Lockpaw in Login Items to finish setting up."
        case .notRegistered: return "Not installed yet."
        case .unavailable: return "This build isn't signed, so the helper can't run."
        }
    }

    @ViewBuilder
    private var lidHelperControl: some View {
        switch lidSleep.helperStatus {
        case .enabled:
            Label("Ready", systemImage: "checkmark.circle.fill")
                .foregroundStyle(settingsAccentColor)
        case .requiresApproval:
            Button("Open Login Items") { lidSleep.openLoginItems() }
        case .notRegistered:
            Button("Install") { lidSleep.setEnabled(true) }
        case .unavailable:
            Label("Unavailable", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(Color("LockpawAmber"))
        }
    }
}

/// Click, then press the new shortcut. A system shortcut it would collide with is refused
/// with the reason; Esc cancels.
private struct HotkeyRecorder: View {
    @AppStorage("hotkeyDisplay") private var display = HotkeyConfig.defaultDisplay
    @State private var isRecording = false
    @State private var conflict: String?
    @State private var monitor: Any?

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Button {
                isRecording ? stop() : start()
            } label: {
                Text(isRecording ? "Press a shortcut\u{2026}" : display)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(isRecording ? settingsAccentColor : .primary)
                    .frame(minWidth: 120)
            }
            .accessibilityLabel(isRecording ? "Recording shortcut" : "Shortcut \(display)")
            .accessibilityHint("Click, then press the new shortcut.")

            if let conflict {
                Text(conflict)
                    .font(.caption)
                    .foregroundStyle(Color("LockpawError"))
            }
        }
        .onDisappear(perform: stop)
    }

    private func start() {
        conflict = nil
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Only ever record in Settings with the screen unlocked: on the lock screen the
            // password field's keystrokes reach local monitors too, and a recorder still
            // listening would turn a typed capital letter into the unlock shortcut.
            guard LockStatus.shared.state == .unlocked else {
                stop()
                return event
            }
            if event.keyCode == UInt16(kVK_Escape) {
                stop()
                return nil
            }
            var parts: [String] = []
            if event.modifierFlags.contains(.command) { parts.append("Cmd") }
            if event.modifierFlags.contains(.shift) { parts.append("Shift") }
            if event.modifierFlags.contains(.option) { parts.append("Opt") }
            if event.modifierFlags.contains(.control) { parts.append("Ctrl") }

            guard !parts.isEmpty else { return event }
            // Shift alone is just a capital letter in every app.
            guard event.modifierFlags.contains(.command) || event.modifierFlags.contains(.option)
                    || event.modifierFlags.contains(.control) else {
                conflict = "Add Command, Option or Control."
                return nil
            }

            if let chars = event.charactersIgnoringModifiers?.uppercased(), !chars.isEmpty {
                parts.append(chars)
            }
            let newDisplay = parts.joined(separator: "+")

            if let system = HotkeyConfig.systemConflict(keyCode: Int(event.keyCode), modifiers: event.modifierFlags) {
                conflict = "\(newDisplay) is taken by \(system)."
                return nil
            }

            var carbonMods = 0
            if event.modifierFlags.contains(.command) { carbonMods |= cmdKey }
            if event.modifierFlags.contains(.shift) { carbonMods |= shiftKey }
            if event.modifierFlags.contains(.option) { carbonMods |= optionKey }
            if event.modifierFlags.contains(.control) { carbonMods |= controlKey }

            HotkeyConfig.saveKeyCode(Int(event.keyCode))
            HotkeyConfig.saveModifiers(carbonMods)
            HotkeyConfig.saveDisplay(newDisplay)
            display = newDisplay
            conflict = nil
            stop()
            NotificationCenter.default.post(name: .lockpawHotkeyPreferenceChanged, object: nil)
            return nil
        }
    }

    private func stop() {
        isRecording = false
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
}
