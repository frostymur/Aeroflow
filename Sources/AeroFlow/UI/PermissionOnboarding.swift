// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM
// Copyright (C) 2026 Timur Iskakov — https://github.com/frostymur

import AppKit
import SwiftUI

/// One-time onboarding for the Accessibility permission. AeroFlow is a
/// headless agent (no menu bar item, no main window), so without this a
/// user who dismisses the system prompt has no in-app way to grant the
/// permission the WM depends on.
///
/// Behavior: shown whenever the permission state transitions to "not
/// granted" (first launch, or a later revocation). The user can dismiss
/// it for the current denial; it returns automatically if the permission
/// is revoked again. When the permission lands, it flashes a confirmation
/// and closes itself — the services start without a relaunch.
@MainActor
final class PermissionOnboardingController: NSObject, NSWindowDelegate {
    static let shared = PermissionOnboardingController()

    private let model = PermissionOnboardingModel()
    private var window: NSWindow?
    private var closeTask: Task<Void, Never>?
    private var lastGranted: Bool?
    private var dismissedForCurrentDenial = false

    override private init() {
        super.init()
    }

    /// Feed the permission monitor's transitions into the onboarding UI.
    func stateChanged(granted: Bool) {
        let flipped = lastGranted != granted
        lastGranted = granted

        if granted {
            guard flipped else { return }
            dismissedForCurrentDenial = false
            guard window != nil else { return }
            model.status = .granted
            closeTask?.cancel()
            closeTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(1.4))
                guard !Task.isCancelled else { return }
                self?.hideWindow()
            }
            return
        }

        if flipped {
            dismissedForCurrentDenial = false
        }
        model.status = .waiting
        presentWindowIfNeeded()
    }

    /// Close without counting as a user dismissal (used after grant).
    func hideWindow() {
        closeTask?.cancel()
        window?.orderOut(nil)
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        // Only fires on an explicit close (the red button); programmatic
        // hides use orderOut and skip this path.
        guard model.status != .granted else { return }
        dismissedForCurrentDenial = true
    }

    // MARK: - Window

    private func presentWindowIfNeeded() {
        guard !dismissedForCurrentDenial else { return }
        if window == nil {
            createWindow()
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
    }

    private func createWindow() {
        let hosting = NSHostingView(
            rootView: PermissionOnboardingView(
                model: model,
                onOpenSettings: { [weak self] in self?.openAccessibilitySettings() },
                onDismiss: { [weak self] in self?.window?.close() }
            )
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 300),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "AeroFlow"
        window.contentView = hosting
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.center()
        window.delegate = self

        // Keep the WM from tiling/hiding our own onboarding window.
        OwnedWindowRegistry.shared.register(window)
        self.window = window
    }

    private func openAccessibilitySettings() {
        let candidates = [
            // macOS 13+
            URL(string: "x-apple.systempreferences:com.apple.extensions.settings?Privacy_Accessibility")!,
            // Legacy
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        ]
        for url in candidates {
            if NSWorkspace.shared.urlForApplication(toOpen: url) != nil {
                NSWorkspace.shared.open(url)
                return
            }
        }
    }
}

@MainActor @Observable
final class PermissionOnboardingModel {
    enum Status {
        case waiting
        case granted
    }

    var status: Status = .waiting
}

private struct PermissionOnboardingView: View {
    let model: PermissionOnboardingModel
    let onOpenSettings: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: model.status == .granted ? "checkmark.circle.fill" : "hand.point.up.left.fill")
                .font(.system(size: 44))
                .foregroundStyle(model.status == .granted ? .green : Color.accentColor)

            Text(model.status == .granted ? "Permission granted" : "Accessibility access required")
                .font(.title3.bold())

            Text(
                model.status == .granted
                    ? "AeroFlow is starting. This window closes automatically."
                    : "AeroFlow moves, resizes, and switches your windows through the macOS Accessibility API. Turn AeroFlow on in the Accessibility settings — it starts automatically, no restart needed."
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)

            if model.status == .waiting {
                HStack(spacing: 10) {
                    Button("Open Accessibility Settings", action: onOpenSettings)
                        .buttonStyle(.borderedProminent)
                    Button("Later", action: onDismiss)
                        .buttonStyle(.bordered)
                }
                .controlSize(.large)
                .padding(.top, 4)
            }
        }
        .padding(28)
        .frame(width: 460)
    }
}
