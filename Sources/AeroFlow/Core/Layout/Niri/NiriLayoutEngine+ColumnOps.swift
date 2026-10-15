// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM
// Copyright (C) 2026 Timur Iskakov — https://github.com/frostymur

import AppKit
import Foundation

extension NiriLayoutEngine {
    struct ColumnRenderPosition {
        let primaryPosition: CGFloat
        let renderOffset: CGPoint

        func displacement(
            to target: Self,
            secondary: CGFloat,
            orientation: Monitor.Orientation
        ) -> CGPoint {
            let sourceRender = switch orientation {
            case .horizontal: renderOffset.x
            case .vertical: renderOffset.y
            }
            let targetRender = switch orientation {
            case .horizontal: target.renderOffset.x
            case .vertical: target.renderOffset.y
            }
            let primary = primaryPosition + sourceRender - target.primaryPosition - targetRender
            return switch orientation {
            case .horizontal: CGPoint(x: primary, y: secondary)
            case .vertical: CGPoint(x: secondary, y: primary)
            }
        }
    }

    struct ColumnTransferResult {
        let sourceBecameEmpty: Bool
        let sourceColumnIndexBeforeCleanup: Int
        let targetColumnIndexAfterInsert: Int
    }

    enum TargetColumnInsertionPolicy {
        case append
        case visualBottom

        func insertionIndex(in targetColumn: NiriContainer) -> Int {
            switch self {
            case .append:
                targetColumn.children.count
            case .visualBottom:
                visualBottomInsertionIndex(in: targetColumn)
            }
        }

        private func visualBottomInsertionIndex(in _: NiriContainer) -> Int {
            // Current child ordering renders index 0 at the visual bottom of a column.
            0
        }
    }

    func resetMovedWindowColumnLocalSizing(_ window: NiriWindow) {
        window.height = .default
        window.windowWidth = .default
        window.resolvedHeight = nil
        window.resolvedWidth = nil
        window.heightFixedByConstraint = false
        window.widthFixedByConstraint = false
    }

    func primarySizeKeyPath(
        for orientation: Monitor.Orientation
    ) -> KeyPath<NiriContainer, CGFloat> {
        switch orientation {
        case .horizontal: \.cachedWidth
        case .vertical: \.cachedHeight
        }
    }

    func primaryDisplacement(
        _ primary: CGFloat,
        secondary: CGFloat = 0,
        orientation: Monitor.Orientation
    ) -> CGPoint {
        switch orientation {
        case .horizontal: CGPoint(x: primary, y: secondary)
        case .vertical: CGPoint(x: secondary, y: primary)
        }
    }

    func animateTransferredWindow(
        _ window: NiriWindow,
        from source: ColumnRenderPosition,
        to target: ColumnRenderPosition,
        secondary: CGFloat,
        context: NiriInteractionContext
    ) {
        let displacement = source.displacement(
            to: target,
            secondary: secondary,
            orientation: context.orientation
        )
        if displacement.x != 0 || displacement.y != 0 {
            window.animateMoveFrom(
                displacement: displacement,
                clock: animationClock,
                config: windowMovementAnimationConfig,
                displayRefreshRate: displayRefreshRate(in: context.workspaceId),
                animated: context.motion.animationsEnabled
            )
        }
    }

    @discardableResult
    func moveWindowToColumn(
        _ node: NiriWindow,
        from sourceColumn: NiriContainer,
        to targetColumn: NiriContainer,
        in workspaceId: WorkspaceDescriptor.ID,
        targetInsertionPolicy: TargetColumnInsertionPolicy = .append,
        activateInsertedWindowInTarget: Bool = false
    ) -> ColumnTransferResult {
        let sourceColumnIndexBeforeCleanup = columnIndex(of: sourceColumn, in: workspaceId) ?? 0
        let sourceWasTabbed = sourceColumn.displayMode == .tabbed
        let targetActiveTileIdxBeforeInsert = targetColumn.activeTileIdx
        sourceColumn.adjustActiveTileIdxForRemoval(of: node)

        node.detach()
        let insertedIndex = targetInsertionPolicy
            .insertionIndex(in: targetColumn)
            .clamped(to: 0 ... targetColumn.children.count)
        targetColumn.insertChild(node, at: insertedIndex)
        NiriLayoutTrace.record(
            .insertion,
            workspaceId: workspaceId,
            "moveToColumn index=\(insertedIndex) policy=\(String(describing: targetInsertionPolicy)) count=\(targetColumn.children.count)"
        )
        resetMovedWindowColumnLocalSizing(node)

        if sourceWasTabbed, !sourceColumn.children.isEmpty {
            sourceColumn.clampActiveTileIdx()
            updateTabbedColumnVisibility(column: sourceColumn)
        }

        if activateInsertedWindowInTarget {
            targetColumn.setActiveTileIdx(insertedIndex)
        } else if insertedIndex <= targetActiveTileIdxBeforeInsert {
            targetColumn.setActiveTileIdx(targetActiveTileIdxBeforeInsert + 1)
        }

        if targetColumn.displayMode == .tabbed {
            updateTabbedColumnVisibility(column: targetColumn)
        } else {
            node.isHiddenInTabbedMode = false
        }

        return ColumnTransferResult(
            sourceBecameEmpty: sourceColumn.children.isEmpty,
            sourceColumnIndexBeforeCleanup: sourceColumnIndexBeforeCleanup,
            targetColumnIndexAfterInsert: columnIndex(of: targetColumn, in: workspaceId) ??
                sourceColumnIndexBeforeCleanup
        )
    }

    func insertWindowInNewColumn(
        _ window: NiriWindow,
        insertIndex: Int,
        context: NiriInteractionContext,
        state: inout ViewportState,
        sizingPolicy: NewContainerSizingPolicy = .workspaceDefault
    ) -> Bool {
        assertSanctionedMutation()
        guard let root = root(for: context.workspaceId) else { return false }
        guard let sourceColumn = findColumn(containing: window, in: context.workspaceId) else { return false }

        let sourceWasTabbed = sourceColumn.displayMode == .tabbed
        sourceColumn.adjustActiveTileIdxForRemoval(of: window)

        let newColumn = NiriContainer()
        switch sizingPolicy {
        case .workspaceDefault:
            initializeNewContainerSizing(newColumn, in: context.workspaceId)
        case .inheritSource:
            copyContainerSizingState(from: sourceColumn, to: newColumn)
        }

        let cols = columns(in: context.workspaceId)
        let clampedIndex = insertIndex.clamped(to: 0 ... cols.count)
        if clampedIndex >= cols.count {
            root.appendChild(newColumn)
        } else {
            root.insertBefore(newColumn, reference: cols[clampedIndex])
        }

        if let newColIdx = columnIndex(of: newColumn, in: context.workspaceId) {
            animateColumnsForAddition(
                columnIndex: newColIdx,
                context: context,
                state: state
            )
        }

        window.detach()
        newColumn.appendChild(window)
        window.isHiddenInTabbedMode = false

        if sourceWasTabbed, !sourceColumn.children.isEmpty {
            sourceColumn.clampActiveTileIdx()
            updateTabbedColumnVisibility(column: sourceColumn)
        }

        cleanupEmptyColumn(sourceColumn, in: context.workspaceId, state: &state)

        ensureSelectionVisible(
            node: window,
            context: context,
            state: &state
        )

        return true
    }

    func cleanupEmptyColumn(
        _ column: NiriContainer,
        in workspaceId: WorkspaceDescriptor.ID,
        state: inout ViewportState
    ) {
        guard column.children.isEmpty else { return }

        // Window-close removals use removeWindows(...); this is structural cleanup for move/consume paths.
        column.remove()
    }

    private func clampedSpan(
        _ span: CGFloat,
        to bounds: (min: CGFloat, max: CGFloat?)
    ) -> CGFloat {
        let lowerBounded = max(span, bounds.min)
        return bounds.max.map { min(lowerBounded, $0) } ?? lowerBounded
    }

    @discardableResult
    func balanceSizes(
        in workspaceId: WorkspaceDescriptor.ID,
        motion: MotionSnapshot,
        workingFrame: CGRect,
        gaps: CGFloat,
        orientation: Monitor.Orientation
    ) -> Bool {
        assertSanctionedMutation()
        let columns = projectedColumns(in: workspaceId)
        guard !columns.isEmpty else { return false }

        let resolvedWidth = resolvedContainerResetPrimarySpan(in: workspaceId)
        switch orientation {
        case .horizontal:
            let targetPixels = (workingFrame.width - gaps) * resolvedWidth.proportion - gaps
            for projectedColumn in columns {
                let column = projectedColumn.column
                column.width = .proportion(resolvedWidth.proportion)
                column.isFullWidth = false
                column.savedWidth = nil
                column.presetWidthIdx = resolvedWidth.presetWidthIdx
                column.hasManualSingleWindowWidthOverride = false

                column.animateWidthTo(
                    newWidth: clampedSpan(
                        targetPixels,
                        to: projectedWidthBounds(for: column, workspaceId: workspaceId)
                    ),
                    clock: animationClock,
                    config: windowMovementAnimationConfig,
                    displayRefreshRate: displayRefreshRate(in: workspaceId),
                    animated: motion.animationsEnabled
                )

                for window in projectedColumn.windows {
                    window.size = 1.0
                }
            }
        case .vertical:
            let targetPixels = (workingFrame.height - gaps) * resolvedWidth.proportion - gaps
            for projectedColumn in columns {
                let column = projectedColumn.column
                column.height = .proportion(resolvedWidth.proportion)
                column.isFullHeight = false
                column.savedHeight = nil
                column.hasManualSingleWindowHeightOverride = false
                column.cachedHeight = clampedSpan(
                    targetPixels,
                    to: projectedHeightBounds(for: column, workspaceId: workspaceId)
                )

                for window in projectedColumn.windows {
                    window.windowWidth = .auto(weight: 1)
                }
            }
        }
        return true
    }

    /// New columns arrive with the default span and existing columns keep
    /// theirs, so a workspace with more columns than the frame can hold
    /// (default span 0.5 ⇒ 3 columns already overflow) lays out wider than
    /// the screen and the viewport camera scrolls on focus switches. After a
    /// column is added, scale the flexible (proportional) columns — including
    /// the new one — so the spans fill the working frame exactly. Columns
    /// pinned by a manual resize (`.fixed`) or marked full-span keep their
    /// size, so intentional overflow (niri's native scroll) is preserved.
    @discardableResult
    func rebalanceColumnsToFit(
        in workspaceId: WorkspaceDescriptor.ID,
        workingFrame: CGRect,
        gaps: CGFloat,
        orientation: Monitor.Orientation
    ) -> Bool {
        let projected = projectedColumns(in: workspaceId)
        guard projected.count > 1 else { return false }

        let axisSpan = orientation == .horizontal ? workingFrame.width : workingFrame.height
        let reservedGaps = gaps * CGFloat(projected.count - 1)
        let available = axisSpan - reservedGaps
        guard available > 0 else { return false }

        struct Entry {
            let column: NiriContainer
            let committed: Bool
            let span: CGFloat
            let minSpan: CGFloat
        }

        var entries: [Entry] = []
        entries.reserveCapacity(projected.count)
        for projected in projected {
            let column = projected.column
            let isFull = orientation == .horizontal ? column.isFullWidth : column.isFullHeight
            let spec = isFull
                ? ProportionalSize.proportion(1)
                : (orientation == .horizontal ? column.width : column.height)
            // Committed = intentionally sized and must not be scaled: a
            // manual resize (`.fixed`, or a manual `.proportion`/preset, which
            // sets the per-axis override flag) or a full-span column. Fresh
            // default columns (override flag false) are scaled to fit.
            let manualOverride = orientation == .horizontal
                ? column.hasManualSingleWindowWidthOverride
                : column.hasManualSingleWindowHeightOverride
            let isCommitted: Bool
            switch spec {
            case .proportion:
                isCommitted = isFull || manualOverride
            case .fixed:
                isCommitted = true
            }
            let span: CGFloat
            switch spec {
            case let .proportion(proportion):
                span = available * proportion
            case let .fixed(size):
                span = size
            }
            let minSpan = orientation == .horizontal
                ? column.widthBounds().min
                : column.heightBounds().min
            entries.append(
                Entry(
                    column: column,
                    committed: isCommitted,
                    span: span,
                    minSpan: minSpan
                )
            )
        }

        let committedTotal = entries.lazy.filter(\.committed).reduce(0) { $0 + $1.span }
        guard committedTotal < available else { return false }
        let flexible = entries.filter { !$0.committed }
        let flexibleTotal = flexible.reduce(0) { $0 + $1.span }
        // Only shrink to fit; never expand columns that already fit.
        guard flexibleTotal > available - committedTotal + 0.5 else { return false }

        let target = available - committedTotal
        let scale = target / flexibleTotal
        var spans = flexible.map { max($0.span * scale, $0.minSpan) }
        // If content minimums kept some column from shrinking, shrink the rest
        // a little more so the total still fits.
        let overflow = spans.reduce(0, +) - target
        if overflow > 0.5 {
            let shrinkable = spans.enumerated().filter { $0.element > flexible[$0.offset].minSpan + 0.5 }
            if !shrinkable.isEmpty {
                let shrinkableTotal = shrinkable.reduce(0) { $0 + $1.element }
                let scale = (shrinkableTotal - overflow) / shrinkableTotal
                for index in shrinkable.map(\.offset) {
                    spans[index] = max(spans[index] * scale, flexible[index].minSpan)
                }
            }
        }
        guard spans.reduce(0, +) < flexibleTotal else { return false }

        for (index, entry) in flexible.enumerated() {
            let proportion = (spans[index] / available).clamped(to: 0.01 ... 1)
            if orientation == .horizontal {
                entry.column.width = .proportion(proportion)
                entry.column.cachedWidth = 0
                entry.column.isFullWidth = false
                entry.column.savedWidth = nil
                entry.column.hasManualSingleWindowWidthOverride = false
                entry.column.presetWidthIdx = nil
            } else {
                entry.column.height = .proportion(proportion)
                entry.column.cachedHeight = 0
                entry.column.isFullHeight = false
                entry.column.savedHeight = nil
                entry.column.hasManualSingleWindowHeightOverride = false
                entry.column.presetWidthIdx = nil
            }
        }
        return true
    }

    func ensureColumnVisible(
        _ column: NiriContainer,
        context: NiriInteractionContext,
        state: inout ViewportState,
        animationConfig: SpringConfig? = nil,
        fromContainerIndex: Int? = nil,
        previousProjectedAnchor: NiriProjectedViewportAnchor? = nil
    ) {
        if let firstWindow = projectedWindows(in: column, workspaceId: context.workspaceId).first {
            ensureSelectionVisible(
                node: firstWindow,
                context: context,
                state: &state,
                animationConfig: animationConfig,
                fromContainerIndex: fromContainerIndex,
                previousProjectedAnchor: previousProjectedAnchor
            )
        }
    }
}
