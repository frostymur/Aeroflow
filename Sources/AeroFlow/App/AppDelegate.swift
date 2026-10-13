// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM
// Copyright (C) 2026 Timur Iskakov — https://github.com/frostymur

import AeroFlowIPC
import AppKit
import Observation
import os

private let appLogger = Logger(subsystem: "com.frostymur.AeroFlow", category: "app")

@MainActor @Observable
public final class AppBootstrapState {
    var settings: SettingsStore?
    var controller: WMController?

    public init() {}

    public var isReady: Bool {
        settings != nil && controller != nil
    }
}

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    public nonisolated(unsafe) weak static var sharedBootstrap: AppBootstrapState?

    override public init() {
        super.init()
    }

    private var ipcServer: IPCServerLifecycle?
    private var runtimeStateStore: RuntimeStateStore?
    private var didFinishBootstrap = false
    private var terminationPending = false
    private var permissionPollTask: Task<Void, Never>?
    private var loggedConflict = false

    public func applicationDidFinishLaunching(_: Notification) {
        NSApplication.shared.setActivationPolicy(.prohibited)
        _ = AeroFlowBuildInfo.executableSHA256
        bootstrapApplication()
    }

    public func applicationWillTerminate(_: Notification) {
        if let controller = AppDelegate.sharedBootstrap?.controller {
            if !terminationPending { controller.serviceLifecycleManager.stop() }
            controller.workspaceManager.flushPersistedWindowRestoreCatalogNow()
        }
        AppDelegate.sharedBootstrap?.settings?.flushNow()
        permissionPollTask?.cancel()
        stopIPCServer()
        runtimeStateStore?.flushNow()
    }

    private func bootstrapApplication() {
        LaunchConflictGate.run(
            scan: { LaunchConflictChecker().scan() },
            present: { reason in
                if !self.loggedConflict {
                    appLogger
                        .error(
                            "Another window manager is running (\(String(describing: reason))); waiting for it to exit."
                        )
                    self.loggedConflict = true
                }
                Thread.sleep(forTimeInterval: 1)
                return .checkAgain
            },
            onClear: { self.beginPermissionGate() },
            onQuit: { NSApplication.shared.terminate(nil) }
        )
    }

    private func beginPermissionGate() {
        guard !didFinishBootstrap else { return }
        if Self.requiredPermissionsGranted() {
            finishBootstrap()
            return
        }
        // Headless app: the onboarding window is the single permission UI —
        // no native system dialog on top of it (that was the redundant
        // second window). prompt:false still records the request in tccd, so
        // the app appears in the Accessibility list the window deep-links to.
        PermissionOnboardingController.shared.stateChanged(granted: false)
        // NSDictionary literal form (as in AXManager+Applications): the
        // `as CFDictionary` cast on a [String: Bool] literal crashed inside
        // AXIsProcessTrustedWithOptions on first ungranted launch (SIGSEGV in
        // CFGetTypeID) and killed the app before any prompt could appear.
        let options: NSDictionary = [axTrustedCheckOptionPrompt as NSString: false]
        _ = AXIsProcessTrustedWithOptions(options)
        appLogger
            .notice(
                "Accessibility not granted yet; AeroFlow starts once it is granted (onboarding window, or System Settings → Privacy & Security)."
            )
        permissionPollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled, !Self.requiredPermissionsGranted() {
                try? await Task.sleep(for: .seconds(1))
            }
            guard !Task.isCancelled else { return }
            PermissionOnboardingController.shared.stateChanged(granted: true)
            self?.finishBootstrap()
        }
    }

    private static func requiredPermissionsGranted() -> Bool {
        // Accessibility is the only required TCC permission (all window
        // operations are AX). Input Monitoring is requested later, when
        // side-specific hotkeys actually need it (HotkeyCenter) — gating the
        // whole WM on it left users stuck after granting Accessibility.
        AXIsProcessTrusted()
    }

    func finishBootstrap() {
        guard !didFinishBootstrap else { return }
        didFinishBootstrap = true

        let storagePaths = AeroFlowStoragePaths.live
        let runtimeState = RuntimeStateStore(directory: storagePaths.stateDirectory)
        self.runtimeStateStore = runtimeState

        let settings = SettingsStore(
            persistence: SettingsFilePersistence(directory: storagePaths.configDirectory),
            runtimeState: runtimeState
        )
        let controller = WMController(settings: settings)
        controller.applyPersistedSettings(settings)
        startSystemMotionPreferenceObservation(controller)

        AppDelegate.sharedBootstrap?.settings = settings
        AppDelegate.sharedBootstrap?.controller = controller

        FatalCapture.install(controllerProvider: { AppDelegate.sharedBootstrap?.controller })
        controller.pendingCrashReport = FatalCapture.consumePending()

        do {
            _ = try AppCLIManager().installCLIToPATH()
        } catch {
            appLogger.error("Could not install aeroflowctl to PATH: \(error.localizedDescription)")
        }

        observeSettings(settings, controller: controller)
        do {
            try setIPCEnabled(settings.ipcEnabled, controller: controller)
        } catch {
            appLogger.error("IPC failed to start: \(error.localizedDescription)")
            settings.ipcEnabled = false
        }

        appLogger.notice("AeroFlow started.")
    }

    private func observeSettings(_ settings: SettingsStore, controller: WMController) {
        settings.onIPCEnabledChanged = { [weak self, weak controller] isEnabled in
            guard let self, let controller else { return }
            do {
                try self.setIPCEnabled(isEnabled, controller: controller)
            } catch {
                appLogger.error("IPC failed to start: \(error.localizedDescription)")
                if isEnabled {
                    settings.ipcEnabled = false
                }
            }
        }
        settings.onExternalSettingsReloaded = { [weak controller] in
            guard let controller else { return }
            controller.applyPersistedSettings(settings)
        }
        settings.onConfigNoticeChanged = { [weak controller] in
            controller?.refreshDiagnosticsIssues()
        }
    }

    func startIPCServer(controller: WMController) throws {
        if ipcServer != nil {
            stopIPCServer()
        }
        let server = IPCServer(controller: controller)
        try server.start()
        ipcServer = server
    }

    func setIPCEnabled(_ enabled: Bool, controller: WMController) throws {
        if enabled {
            try startIPCServer(controller: controller)
        } else {
            stopIPCServer()
        }
    }

    private func stopIPCServer() {
        ipcServer?.stop()
        ipcServer = nil
    }

    private func startSystemMotionPreferenceObservation(_ controller: WMController) {
        controller.motionPolicy.systemReducesMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        _ = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
        ) { [weak controller] _ in
            Task { @MainActor [weak controller] in
                controller?.motionPolicy.systemReducesMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            }
        }
    }
}

extension AppDelegate {
    public func applicationShouldTerminate(_ application: NSApplication) -> NSApplication.TerminateReply {
        guard let controller = AppDelegate.sharedBootstrap?.controller else { return .terminateNow }
        return deferTermination(
            stop: { completion in
                Task { @MainActor in
                    controller.serviceLifecycleManager.stopRestoringWindows(forQuit: true, completion: completion)
                }
            },
            reply: {
                controller.workspaceManager.flushPersistedWindowRestoreCatalogNow()
                application.reply(toApplicationShouldTerminate: true)
            }
        )
    }

    func deferTermination(
        stop: @escaping (@escaping @MainActor @Sendable () -> Void) -> Void,
        reply: @escaping @MainActor @Sendable () -> Void
    ) -> NSApplication.TerminateReply {
        guard !terminationPending else { return .terminateLater }
        terminationPending = true
        Task { @MainActor in stop(reply) }
        return .terminateLater
    }
}
