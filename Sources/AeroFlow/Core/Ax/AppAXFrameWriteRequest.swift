// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM
// Copyright (C) 2026 Timur Iskakov — https://github.com/frostymur

import AppKit
import ApplicationServices
import Dispatch
import Foundation

struct AppAXFrameWriteRequest: Sendable {
    let requestId: AXFrameRequestId
    let pid: pid_t
    let windowId: Int
    let expectedWindow: AXWindowRef
    let frame: CGRect
    let currentFrameHint: CGRect?
    let components: AXFrameComponents
    let generation: UInt64
    let verify: Bool
    let traceRequestId: UInt64
    /// Park lane only: treat a readback that is off by the OS title-bar
    /// clamp (see `parkClampTolerance`) as verified success instead of
    /// `verificationMismatch`.
    let clampTolerant: Bool

    init(
        requestId: AXFrameRequestId,
        pid: pid_t,
        windowId: Int,
        expectedWindow: AXWindowRef,
        frame: CGRect,
        currentFrameHint: CGRect?,
        components: AXFrameComponents = .all,
        generation: UInt64,
        verify: Bool,
        traceRequestId: UInt64 = 0,
        clampTolerant: Bool = false
    ) {
        self.requestId = requestId
        self.pid = pid
        self.windowId = windowId
        self.expectedWindow = expectedWindow
        self.frame = frame
        self.currentFrameHint = currentFrameHint
        self.components = components
        self.generation = generation
        self.verify = verify
        self.traceRequestId = traceRequestId
        self.clampTolerant = clampTolerant
    }
}

struct AppAXClosingFrameWriteRequest: Sendable {
    let target: AXClosingFrameTarget
    let generation: UInt64
}
