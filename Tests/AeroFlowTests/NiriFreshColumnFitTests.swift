// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM
// Copyright (C) 2026 Timur Iskakov — https://github.com/frostymur

@testable import AeroFlow
import CoreGraphics
import XCTest

/// A proportional column span reserves one inner gap per sibling, so a span
/// cached while a column was alone is wider than the fit. Adding or removing
/// columns must re-resolve derived spans, otherwise fresh windows overflow the
/// working frame by half a gap.
///
/// Live evidence: on a 1470x956 display (outer gaps 8, inner gap 16) two fresh
/// windows came back 727 + 719 px wide with a 16 pt gap between them, i.e.
/// 1462 > 1454 of working width, so the trailing window landed flush against
/// the screen edge instead of inside the outer gap.
final class NiriFreshColumnFitTests: XCTestCase {
    private let workingFrame = CGRect(x: 8, y: 8, width: 1454, height: 908)
    private let gap: CGFloat = 16

    private func resolveSpans(
        _ engine: NiriLayoutEngine,
        in workspaceId: WorkspaceDescriptor.ID,
        orientation: Monitor.Orientation
    ) {
        engine.resolvePrimaryContainerSpans(
            in: workspaceId,
            workingFrame: workingFrame,
            gaps: gap,
            orientation: orientation
        )
    }

    private func addWindow(
        _ engine: NiriLayoutEngine,
        windowId: Int,
        to workspaceId: WorkspaceDescriptor.ID,
        after node: NiriNode? = nil
    ) -> NiriWindow {
        engine.addWindow(
            token: WindowToken(pid: 9_001, windowId: windowId),
            to: workspaceId,
            afterSelection: node?.id
        )
    }

    /// Two fresh windows must split the working frame exactly: both columns
    /// resolve as (1454 - 16) * 0.5 = 719, not the stale 727 from a lone
    /// column, and neither frame leaves the working frame.
    func testSecondFreshWindowFitsTheWorkingFrame() {
        let engine = NiriLayoutEngine()
        let workspaceId = WorkspaceDescriptor.ID()

        let first = addWindow(engine, windowId: 1, to: workspaceId)
        resolveSpans(engine, in: workspaceId, orientation: .horizontal)
        XCTAssertEqual(
            engine.findColumn(containing: first, in: workspaceId)?.cachedWidth ?? 0,
            workingFrame.width * 0.5,
            accuracy: 0.5
        )

        let second = addWindow(engine, windowId: 2, to: workspaceId, after: first)
        resolveSpans(engine, in: workspaceId, orientation: .horizontal)

        let columns = engine.columns(in: workspaceId)
        XCTAssertEqual(columns.count, 2)
        let spans = columns.map(\.cachedWidth)
        XCTAssertEqual(spans[0], spans[1], accuracy: 0.5)
        XCTAssertEqual(spans[0], (workingFrame.width - gap) * 0.5, accuracy: 0.5)
        XCTAssertLessThanOrEqual(spans.reduce(0, +) + gap, workingFrame.width + 0.5)

        var state = ViewportState()
        state.selectedNodeId = second.id
        let frames = engine.calculateLayout(
            state: state,
            workspaceId: workspaceId,
            monitorFrame: workingFrame,
            gaps: (horizontal: gap, vertical: gap),
            orientation: .horizontal
        )
        for frame in frames.values {
            XCTAssertGreaterThanOrEqual(frame.minX, workingFrame.minX - 0.5)
            XCTAssertLessThanOrEqual(frame.maxX, workingFrame.maxX + 0.5)
        }
    }

    /// Same asymmetry on the vertical axis: a lone column caches
    /// (908) * 0.5 = 454 and must re-resolve to (908 - 16) * 0.5 = 446.
    func testSecondFreshWindowFitsTheWorkingFrameWhenVertical() {
        let engine = NiriLayoutEngine()
        let workspaceId = WorkspaceDescriptor.ID()

        let first = addWindow(engine, windowId: 1, to: workspaceId)
        resolveSpans(engine, in: workspaceId, orientation: .vertical)

        _ = addWindow(engine, windowId: 2, to: workspaceId, after: first)
        resolveSpans(engine, in: workspaceId, orientation: .vertical)

        let columns = engine.columns(in: workspaceId)
        XCTAssertEqual(columns.count, 2)
        let spans = columns.map(\.cachedHeight)
        XCTAssertEqual(spans[0], spans[1], accuracy: 0.5)
        XCTAssertEqual(spans[0], (workingFrame.height - gap) * 0.5, accuracy: 0.5)
        XCTAssertLessThanOrEqual(spans.reduce(0, +) + gap, workingFrame.height + 0.5)
    }

    /// A column the user pinned keeps its pixels when another window opens;
    /// only derived spans are re-resolved.
    func testPinnedColumnKeepsPixelsWhenAColumnIsAdded() {
        let engine = NiriLayoutEngine()
        let workspaceId = WorkspaceDescriptor.ID()

        let first = addWindow(engine, windowId: 1, to: workspaceId)
        resolveSpans(engine, in: workspaceId, orientation: .horizontal)

        let pinned = engine.findColumn(containing: first, in: workspaceId)
        pinned?.width = .fixed(600)
        pinned?.cachedWidth = 600
        pinned?.hasManualSingleWindowWidthOverride = true

        _ = addWindow(engine, windowId: 2, to: workspaceId, after: first)
        resolveSpans(engine, in: workspaceId, orientation: .horizontal)

        XCTAssertEqual(pinned?.cachedWidth ?? 0, 600, accuracy: 0.5)
    }

    /// Closing the second of two fresh windows returns the survivor to the
    /// lone-column span: the count changed, so the cached span is stale.
    func testRemovingSecondFreshColumnRestoresLoneColumnSpan() {
        let engine = NiriLayoutEngine()
        let workspaceId = WorkspaceDescriptor.ID()

        let first = addWindow(engine, windowId: 1, to: workspaceId)
        resolveSpans(engine, in: workspaceId, orientation: .horizontal)
        let second = addWindow(engine, windowId: 2, to: workspaceId, after: first)
        resolveSpans(engine, in: workspaceId, orientation: .horizontal)
        XCTAssertEqual(engine.columns(in: workspaceId).count, 2)

        var state = ViewportState()
        _ = engine.removeWindows(
            [second.token],
            context: .init(
                workspaceId: workspaceId,
                motion: .disabled,
                workingFrame: workingFrame,
                gaps: gap,
                orientation: .horizontal
            ),
            state: &state,
            selectedNodeId: first.id,
            removedNodeIds: []
        )
        resolveSpans(engine, in: workspaceId, orientation: .horizontal)

        let survivor = engine.findColumn(containing: first, in: workspaceId)
        XCTAssertEqual(survivor?.cachedWidth ?? 0, workingFrame.width * 0.5, accuracy: 0.5)
    }
}
