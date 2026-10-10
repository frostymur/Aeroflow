// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM
// Copyright (C) 2026 Timur Iskakov — https://github.com/frostymur

import AeroFlowIPC
import AppKit
import Foundation

extension WMController {
    func handleSessionStateChanged(surfaceScope: SessionSurfaceInvalidationScope) {
        if surfaceScope == .full {
            surfaceReconciler.noteWorldChanged()
        }
        let changeSet = focusNotificationDispatcher.notifyFocusChangesIfNeeded()
        guard let ipcApplicationBridge else { return }
        // Fast path: publish the latency-critical channels synchronously on
        // the main thread, at the bookkeeping flip itself. Deferring to a
        // Task + actor hop queues the event behind the in-flight relayout
        // (AX writes that occupy the main thread), so subscribers like the
        // bar highlight land tens of ms after the switch.
        if changeSet.focusChanged {
            ipcApplicationBridge.publishEventNow(.focus)
        }
        if changeSet.workspaceChanged || changeSet.monitorChanged {
            ipcApplicationBridge.publishEventNow(.activeWorkspace)
        }
        if changeSet.monitorChanged {
            ipcApplicationBridge.publishEventNow(.focusedMonitor)
            Task {
                await ipcApplicationBridge.publishEvent(.displayChanged)
            }
        }
    }

    func cancelPendingFrameJobsForInvalidation(workspaceId: WorkspaceDescriptor.ID?) {
        let entries = workspaceId.map { workspaceManager.entries(in: $0) } ?? workspaceManager.allEntries()
        guard !entries.isEmpty else { return }
        axManager.cancelPendingFrameJobs(entries.map { ($0.pid, $0.windowId) }, reason: "invalidation")
    }
}
