// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM
// Copyright (C) 2026 Timur Iskakov — https://github.com/frostymur

@testable import AeroFlow
import CoreGraphics
import XCTest

/// New columns arrive with the default span (0.5) and existing columns keep
/// theirs, so adding a third default column overflows the frame (150%) and the
/// viewport camera scrolls on focus switches. After a column is added the
/// flexible columns must be scaled so the spans fill the frame (± rounding).
final class NiriColumnFitRebalanceTests: NiriInteractionTestCase {
    /// The layout rounds non-terminating proportions to whole half-points when
    /// resolving to pixels (e.g. 3×⅓ ⇒ 1600.5), so "fits" is asserted within
    /// a 1pt rounding tolerance — the fix removes the 50% overflow, not the
    /// layout's inherent sub-pixel rounding.
    private let fitTolerance: CGFloat = 1.0

    private let gap: CGFloat = 0

    private func layout(
        _ engine: NiriLayoutEngine,
        in workspaceId: WorkspaceDescriptor.ID,
        selected: NiriWindow
    ) -> [WindowToken: CGRect] {
        var state = ViewportState()
        state.selectedNodeId = selected.id
        return engine.calculateLayout(
            state: state,
            workspaceId: workspaceId,
            monitorFrame: workingFrame,
            gaps: (horizontal: gap, vertical: gap),
            orientation: .horizontal
        )
    }

    /// One window per column ⇒ the window frame width is the column span.
    private func columnWidths(
        _ engine: NiriLayoutEngine,
        in workspaceId: WorkspaceDescriptor.ID,
        selected: NiriWindow
    ) -> [CGFloat] {
        layout(engine, in: workspaceId, selected: selected).values.map(\.width)
    }

    func testAddingThirdDefaultColumnFitsWithinFrame() throws {
        let engine = NiriLayoutEngine()
        let workspaceId = WorkspaceDescriptor.ID()
        let geo = NiriSizingGeometry(workingFrame: workingFrame, gaps: gap, orientation: .horizontal)

        let w1 = addWindow(engine, pid: 9_001, windowId: 1, to: workspaceId, sizingGeometry: geo)
        let w2 = addWindow(engine, pid: 9_002, windowId: 2, to: workspaceId, after: w1, sizingGeometry: geo)

        // Two default columns exactly fill the frame (no overflow yet).
        XCTAssertEqual(
            columnWidths(engine, in: workspaceId, selected: w2).reduce(0, +),
            workingFrame.width,
            accuracy: fitTolerance
        )

        // The third default column would push the total to 150% of the frame;
        // the rebalance must scale the flexible columns back to ~100%.
        let w3 = addWindow(engine, pid: 9_003, windowId: 3, to: workspaceId, sizingGeometry: geo)
        XCTAssertEqual(engine.projectedColumns(in: workspaceId).count, 3)

        let frames = layout(engine, in: workspaceId, selected: w3)
        let total = frames.values.map(\.width).reduce(0, +)
        // Fits: within rounding of the frame, not the 150% it would be without
        // the rebalance.
        XCTAssertLessThanOrEqual(total, workingFrame.width + fitTolerance)
        XCTAssertGreaterThanOrEqual(total, workingFrame.width - fitTolerance)
        for frame in frames.values {
            XCTAssertGreaterThanOrEqual(frame.minX, workingFrame.minX - fitTolerance)
            XCTAssertLessThanOrEqual(frame.maxX, workingFrame.maxX + fitTolerance)
        }
    }

    func testRebalanceScalesFlexibleColumnsToFillEvenly() throws {
        let engine = NiriLayoutEngine()
        let workspaceId = WorkspaceDescriptor.ID()
        let geo = NiriSizingGeometry(workingFrame: workingFrame, gaps: gap, orientation: .horizontal)

        let w1 = addWindow(engine, pid: 9_101, windowId: 1, to: workspaceId, sizingGeometry: geo)
        let w2 = addWindow(engine, pid: 9_102, windowId: 2, to: workspaceId, after: w1, sizingGeometry: geo)
        _ = addWindow(engine, pid: 9_103, windowId: 3, to: workspaceId, after: w2, sizingGeometry: geo)

        let widths = columnWidths(engine, in: workspaceId, selected: w2)
        // Three equal default columns settle to equal thirds of the frame.
        for width in widths {
            XCTAssertEqual(width, workingFrame.width / 3, accuracy: workingFrame.width * 0.02)
        }
        XCTAssertEqual(widths.reduce(0, +), workingFrame.width, accuracy: fitTolerance)
    }

    func testRebalanceRespectsManuallyPinnedColumn() throws {
        let engine = NiriLayoutEngine()
        let workspaceId = WorkspaceDescriptor.ID()
        let geo = NiriSizingGeometry(workingFrame: workingFrame, gaps: gap, orientation: .horizontal)

        let w1 = addWindow(engine, pid: 9_201, windowId: 1, to: workspaceId, sizingGeometry: geo)
        let w2 = addWindow(engine, pid: 9_202, windowId: 2, to: workspaceId, after: w1, sizingGeometry: geo)

        // Manually pin the first column to a fixed 600pt width.
        let firstColumn = try XCTUnwrap(engine.findColumn(containing: w1, in: workspaceId))
        firstColumn.width = .fixed(600)
        firstColumn.cachedWidth = 600

        // Add a third window: the rebalance must scale only the flexible
        // columns, leaving the pinned 600pt column untouched.
        let w3 = addWindow(engine, pid: 9_203, windowId: 3, to: workspaceId, sizingGeometry: geo)

        let widths = columnWidths(engine, in: workspaceId, selected: w3)
        let total = widths.reduce(0, +)
        XCTAssertLessThanOrEqual(total, workingFrame.width + fitTolerance)
        // The pinned column keeps ~600pt.
        let pinned = widths.first { abs($0 - 600) < 1 }
        XCTAssertNotNil(pinned, "the manually pinned column should keep its 600pt width, got \(widths)")
    }
}
