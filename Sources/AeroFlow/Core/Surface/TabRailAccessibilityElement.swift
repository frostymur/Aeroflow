// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM
// Copyright (C) 2026 Timur Iskakov — https://github.com/frostymur

import AppKit

final class TabRailAccessibilityElement: NSAccessibilityElement {
    private weak var parentElement: AnyObject?
    private weak var ownerView: TabRailView?
    private var tab: TabRailTabInfo
    private var hitRectInView: CGRect
    private var screenFrame: CGRect
    private let pressAction: (Int) -> Void
    private let revealAction: (Int) -> Void
    private(set) var isSelected: Bool

    var visualIndex: Int {
        tab.visualIndex
    }

    init(
        parent: AnyObject,
        tab: TabRailTabInfo,
        hitRectInView: CGRect,
        screenFrame: CGRect,
        pressAction: @escaping (Int) -> Void,
        revealAction: @escaping (Int) -> Void = { _ in }
    ) {
        parentElement = parent
        ownerView = parent as? TabRailView
        self.tab = tab
        self.hitRectInView = hitRectInView
        self.screenFrame = screenFrame
        self.pressAction = pressAction
        self.revealAction = revealAction
        isSelected = tab.isActive
        super.init()
    }

    override func isAccessibilityElement() -> Bool {
        true
    }

    override func accessibilityRole() -> NSAccessibility.Role? {
        .radioButton
    }

    override func accessibilityLabel() -> String? {
        tab.accessibilityLabel
    }

    override func accessibilityValue() -> Any? {
        NSNumber(value: isSelected)
    }

    override func accessibilityParent() -> Any? {
        parentElement
    }

    override func accessibilityFrame() -> NSRect {
        // Report the icon's live on-screen position: the rail window can be
        // repositioned after the frame was last cached (window-server
        // settling), and assistive clients must target where the icon is now.
        // Accessibility queries arrive on the main thread; fall back to the
        // cached frame for the off-main edge case.
        guard let view = ownerView, !hitRectInView.isEmpty, Thread.isMainThread else {
            return screenFrame
        }
        let rect = hitRectInView
        return MainActor.assumeIsolated {
            view.screenFrameForAccessibility(for: rect)
        }
    }

    override func isAccessibilityEnabled() -> Bool {
        true
    }

    override func accessibilityPerformPress() -> Bool {
        pressAction(tab.visualIndex)
        return true
    }

    override func setAccessibilityFocused(_ focused: Bool) {
        if focused { revealAction(tab.visualIndex) }
        super.setAccessibilityFocused(focused)
    }

    func update(tab: TabRailTabInfo, hitRectInView: CGRect, screenFrame: CGRect) {
        self.tab = tab
        self.hitRectInView = hitRectInView
        self.screenFrame = screenFrame
    }

    func updateScreenFrame(_ hitRectInView: CGRect, screenFrame: CGRect) {
        self.hitRectInView = hitRectInView
        self.screenFrame = screenFrame
    }

    func updateSelected(_ selected: Bool, postNotification: Bool) {
        guard isSelected != selected else { return }
        isSelected = selected
        if postNotification {
            NSAccessibility.post(element: self, notification: .valueChanged)
        }
    }
}
