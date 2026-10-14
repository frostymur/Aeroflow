// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM
// Copyright (C) 2026 Timur Iskakov — https://github.com/frostymur

@testable import AeroFlow
import CoreGraphics
import XCTest

/// Shrinking a lone window pins a fixed size on it. Growing it back to the top
/// of the available span must return it to true auto sizing (full span) instead
/// of leaving it pinned just short of full — which is what made a shrunk
/// full-height window impossible to restore short of closing it.
final class NiriLoneWindowFullSpanResetTests: NiriInteractionTestCase {
    func testLoneWindowGrownBackToFullReturnsToAutoHeight() throws {
        let engine = NiriLayoutEngine()
        let workspaceId = WorkspaceDescriptor.ID()
        let window = addWindow(engine, pid: 7_001, to: workspaceId)
        var state = ViewportState()
        state.selectedNodeId = window.id
        let geometry = NiriSizingGeometry(
            workingFrame: workingFrame,
            gaps: 0,
            orientation: .horizontal
        )

        let full = try XCTUnwrap(layout(engine, in: workspaceId, state: state)[window.token])
        XCTAssertEqual(full.height, workingFrame.height, accuracy: 0.001)

        // Shrink to 90%: pins a fixed height below full.
        engine.setWindowSecondarySpan(window, change: .setProportion(90), in: workspaceId, geometry: geometry)
        XCTAssertTrue(window.height.isFixed)
        let shrunk = try XCTUnwrap(layout(engine, in: workspaceId, state: state)[window.token])
        XCTAssertLessThan(shrunk.height, workingFrame.height)

        // Grow back to the full span: returns to auto (full height).
        engine.setWindowSecondarySpan(window, change: .setProportion(100), in: workspaceId, geometry: geometry)
        XCTAssertEqual(window.height, .auto(weight: 1))
        let restored = try XCTUnwrap(layout(engine, in: workspaceId, state: state)[window.token])
        XCTAssertEqual(restored.height, workingFrame.height, accuracy: 0.001)
    }

    func testLoneWindowWidthGrownBackToFullReturnsToAutoWidth() throws {
        let engine = NiriLayoutEngine()
        let workspaceId = WorkspaceDescriptor.ID()
        let window = addWindow(engine, pid: 7_002, to: workspaceId)
        var state = ViewportState()
        state.selectedNodeId = window.id
        let portraitFrame = CGRect(x: 0, y: 0, width: 900, height: 1600)
        let geometry = NiriSizingGeometry(
            workingFrame: portraitFrame,
            gaps: 0,
            orientation: .vertical
        )

        func portraitLayout() -> [WindowToken: CGRect] {
            engine.calculateLayout(
                state: state,
                workspaceId: workspaceId,
                monitorFrame: portraitFrame,
                gaps: (horizontal: 0, vertical: 0),
                orientation: .vertical
            )
        }

        let full = try XCTUnwrap(portraitLayout()[window.token])
        XCTAssertEqual(full.width, portraitFrame.width, accuracy: 0.001)

        engine.setWindowSecondarySpan(window, change: .setProportion(90), in: workspaceId, geometry: geometry)
        XCTAssertTrue(window.windowWidth.isFixed)
        let shrunk = try XCTUnwrap(portraitLayout()[window.token])
        XCTAssertLessThan(shrunk.width, portraitFrame.width)

        engine.setWindowSecondarySpan(window, change: .setProportion(100), in: workspaceId, geometry: geometry)
        XCTAssertEqual(window.windowWidth, .auto(weight: 1))
        let restored = try XCTUnwrap(portraitLayout()[window.token])
        XCTAssertEqual(restored.width, portraitFrame.width, accuracy: 0.001)
    }
}
