// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM
// Copyright (C) 2026 Timur Iskakov — https://github.com/frostymur

import AppKit

extension NiriLayoutEngine {
    func calculateVerticalPixelsPerWeightUnit(
        column: NiriContainer,
        workspaceId: WorkspaceDescriptor.ID,
        monitorFrame: CGRect,
        gaps: LayoutGaps
    ) -> CGFloat {
        let windows = projectedWindows(in: column, workspaceId: workspaceId)
        guard !windows.isEmpty else { return 0 }

        let totalWeight = windows.reduce(CGFloat(0)) { $0 + $1.size }
        guard totalWeight > 0 else { return 0 }

        let totalGaps = CGFloat(windows.count + 1) * gaps.vertical
        let usableHeight = monitorFrame.height - totalGaps

        return usableHeight / totalWeight
    }

    func setWindowSizingMode(
        _ window: NiriWindow,
        motion: MotionSnapshot,
        mode: SizingMode,
        state: inout ViewportState
    ) {
        let previousMode = window.sizingMode

        if previousMode == mode {
            return
        }

        if previousMode == .fullscreen, mode == .normal {
            if let savedHeight = window.savedHeight {
                window.height = savedHeight
                window.savedHeight = nil
            }

            if let savedOffset = state.viewOffsetToRestore {
                state.animateViewOffsetRestore(savedOffset, motion: motion)
            }
        }

        if previousMode == .normal, mode == .fullscreen {
            window.savedHeight = window.height
            state.saveViewOffsetForFullscreen()
            window.stopMoveAnimations()
        }

        window.sizingMode = mode
    }

    func toggleFullscreen(
        _ window: NiriWindow,
        motion: MotionSnapshot,
        state: inout ViewportState
    ) {
        assertSanctionedMutation()
        let newMode: SizingMode = window.sizingMode == .fullscreen ? .normal : .fullscreen
        setWindowSizingMode(window, motion: motion, mode: newMode, state: &state)
    }

    func toggleWindowPrimarySpan(
        _ window: NiriWindow,
        forwards: Bool,
        context: NiriInteractionContext,
        state: inout ViewportState
    ) {
        assertSanctionedMutation()
        guard let column = findColumn(containing: window, in: context.workspaceId) else { return }
        toggleContainerPrimarySpan(
            column,
            forwards: forwards,
            context: context,
            state: &state
        )
    }

    func setWindowPrimarySpan(
        _ window: NiriWindow,
        change: NiriSizeChange,
        context: NiriInteractionContext,
        state: inout ViewportState
    ) {
        assertSanctionedMutation()
        guard let column = findColumn(containing: window, in: context.workspaceId) else { return }
        setContainerPrimarySpan(
            column,
            change: change,
            context: context,
            state: &state
        )
    }

    private func availableWindowWidth(
        in column: NiriContainer,
        projectedWindowCount: Int,
        workingFrame: CGRect
    ) -> CGFloat {
        let contentInset = column.isTabbed && projectedWindowCount > 1
            ? tabContentInset(for: column)
            : 0
        return max(1, workingFrame.width - contentInset)
    }

    /// A lone window that is resized up to the top of the available span should
    /// return to true auto sizing (which tracks the full span) rather than being
    /// pinned just short of it. Manual resize otherwise pins a fixed size, which
    /// is capped at `span - 2*gaps` — so without this, growing can never restore
    /// the full height/width the window had before it was shrunk.
    private func loneWindowReachedFullSpan(
        projectedWindows: [NiriWindow],
        newPixels: CGFloat,
        availableSpan: CGFloat,
        gaps: CGFloat
    ) -> Bool {
        projectedWindows.count == 1
            && newPixels >= availableSpan - 2 * gaps - 1
    }

    private func setVerticalWindowWidth(
        _ window: NiriWindow,
        change: NiriSizeChange,
        in column: NiriContainer,
        projectedWindows: [NiriWindow],
        geometry: NiriSizingGeometry
    ) {
        if window.windowWidth.isAuto {
            NiriWindow.normalizeWidthWeights(in: projectedWindows)
        }

        let currentWindowPixels = window.currentWidthForSizing()
        let availableWidth = availableWindowWidth(
            in: column,
            projectedWindowCount: projectedWindows.count,
            workingFrame: geometry.workingFrame
        )
        let windowWidth = change.secondaryPixels(
            currentPixels: currentWindowPixels,
            availableSpan: availableWidth,
            gaps: geometry.gaps
        )

        if loneWindowReachedFullSpan(
            projectedWindows: projectedWindows,
            newPixels: windowWidth,
            availableSpan: availableWidth,
            gaps: geometry.gaps
        ) {
            window.windowWidth = .auto(weight: 1)
            if window.sizingMode == .maximized {
                window.sizingMode = .normal
            }
            return
        }

        column.applyWindowWidth(
            window,
            projectedWindows: projectedWindows,
            pixels: windowWidth,
            availableSpan: availableWidth,
            gaps: geometry.gaps
        )
    }

    func setWindowSecondarySpan(
        _ window: NiriWindow,
        change: NiriSizeChange,
        in workspaceId: WorkspaceDescriptor.ID,
        geometry: NiriSizingGeometry
    ) {
        assertSanctionedMutation()
        guard !isExcludedFromProjection(window.token, in: workspaceId),
              let column = findColumn(containing: window, in: workspaceId)
        else {
            return
        }
        let projectedWindows = projectedWindows(in: column, workspaceId: workspaceId)
        cancelInteractiveResize(for: column, in: workspaceId)
        if geometry.orientation == .vertical {
            setVerticalWindowWidth(
                window,
                change: change,
                in: column,
                projectedWindows: projectedWindows,
                geometry: geometry
            )
            return
        }

        if window.height.isAuto {
            NiriWindow.normalizeHeightWeights(in: projectedWindows)
        }

        let currentWindowPixels = window.currentHeightForSizing()
        let windowHeight = change.secondaryPixels(
            currentPixels: currentWindowPixels,
            availableSpan: geometry.workingFrame.height,
            gaps: geometry.gaps
        )

        if loneWindowReachedFullSpan(
            projectedWindows: projectedWindows,
            newPixels: windowHeight,
            availableSpan: geometry.workingFrame.height,
            gaps: geometry.gaps
        ) {
            window.height = .auto(weight: 1)
            window.savedHeight = nil
            if window.sizingMode == .maximized {
                window.sizingMode = .normal
            }
            return
        }

        column.applyWindowHeight(
            window,
            projectedWindows: projectedWindows,
            pixels: windowHeight,
            availableSpan: geometry.workingFrame.height,
            gaps: geometry.gaps
        )
    }

    func resetWindowSecondarySpan(
        _ window: NiriWindow,
        in workspaceId: WorkspaceDescriptor.ID,
        orientation: Monitor.Orientation
    ) {
        assertSanctionedMutation()
        guard !isExcludedFromProjection(window.token, in: workspaceId),
              let column = findColumn(containing: window, in: workspaceId)
        else {
            return
        }
        let projectedWindows = projectedWindows(in: column, workspaceId: workspaceId)
        cancelInteractiveResize(for: column, in: workspaceId)
        if orientation == .vertical {
            if column.isTabbed {
                for tile in projectedWindows {
                    tile.windowWidth = .auto(weight: 1)
                }
            } else {
                window.windowWidth = .auto(weight: 1)
            }
            return
        }

        if column.isTabbed {
            for tile in projectedWindows {
                tile.height = .auto(weight: 1)
                tile.savedHeight = nil
            }
        } else {
            window.height = .auto(weight: 1)
            window.savedHeight = nil
        }
    }

    func toggleWindowSecondarySpan(
        _ window: NiriWindow,
        forwards: Bool,
        in workspaceId: WorkspaceDescriptor.ID,
        geometry: NiriSizingGeometry
    ) {
        assertSanctionedMutation()
        guard !presetWindowSecondarySpans.isEmpty else { return }
        guard !isExcludedFromProjection(window.token, in: workspaceId),
              let column = findColumn(containing: window, in: workspaceId)
        else {
            return
        }
        let projectedWindows = projectedWindows(in: column, workspaceId: workspaceId)
        cancelInteractiveResize(for: column, in: workspaceId)
        if geometry.orientation == .vertical {
            let availableWidth = availableWindowWidth(
                in: column,
                projectedWindowCount: projectedWindows.count,
                workingFrame: geometry.workingFrame
            )
            if window.windowWidth.isAuto {
                NiriWindow.normalizeWidthWeights(in: projectedWindows)
            }

            let nextIndex = window.nextSecondaryPresetIndex(
                forwards: forwards,
                presets: presetWindowSecondarySpans,
                availableSpan: availableWidth,
                gaps: geometry.gaps,
                orientation: geometry.orientation
            )

            window.windowWidth = .preset(nextIndex)
            if window.sizingMode == .maximized {
                window.sizingMode = .normal
            }
            return
        }

        if window.height.isAuto {
            NiriWindow.normalizeHeightWeights(in: projectedWindows)
        }

        let nextIdx = window.nextSecondaryPresetIndex(
            forwards: forwards,
            presets: presetWindowSecondarySpans,
            availableSpan: geometry.workingFrame.height,
            gaps: geometry.gaps,
            orientation: geometry.orientation
        )

        window.height = .preset(nextIdx)
        window.savedHeight = nil
        if window.sizingMode == .maximized {
            window.sizingMode = .normal
        }
    }
}
