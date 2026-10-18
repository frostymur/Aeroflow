// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM
// Copyright (C) 2026 Timur Iskakov — https://github.com/frostymur

import AeroFlowIPC
import Foundation

// MARK: - SettingsExport

struct SettingsExport: Equatable {
    var hotkeysEnabled: Bool
    var focus: Focus
    var mouseWarp: MouseWarp
    var routing: Routing
    var monitorRanking: [OutputId]
    var gaps: Gaps

    var niri: Niri

    var workspaceConfigurations: [WorkspaceConfiguration]
    var defaultLayoutType: LayoutType

    var hotkeyBindings: [HotkeyBinding]
    var systemHyperTrigger: SystemHyperTrigger
    var hyperKeyModifiers: HyperKeyModifiers

    var appRules: [AppRule]
    var monitorOrientationSettings: [MonitorOrientationSettings]
    var monitorNiriSettings: [MonitorNiriSettings]

    var dwindle: Dwindle
    var monitorDwindleSettings: [MonitorDwindleSettings]

    var monitorGapSettings: [MonitorGapSettings]

    var preventSleepEnabled: Bool
    var ipcEnabled: Bool
    var gestures: Gestures
    var animationsEnabled: Bool
    var animationStyle: AnimationStyle

    var appearanceMode: AppearanceMode
    var tabRailAppIcons: Bool

    struct Focus: Codable, Equatable {
        var followsMouse: Bool
        var raiseOnMouseFocus: Bool
        var lockModifier: FocusLockModifier
        var moveMouseToFocusedWindow: Bool
        var followsWindowToMonitor: Bool
        var crossesMonitorAtEdge: Bool
        var moveCrossesMonitorAtEdge: Bool
    }

    struct MouseWarp: Codable, Equatable {
        var margin: Int
        var enabled: Bool
        var constrainToArrangement: Bool
    }

    struct Routing: Codable, Equatable {
        var mode: MonitorRoutingMode
        var arrangements: [MonitorArrangement]
    }

    struct Gaps: Codable, Equatable {
        var size: Double
        var fullscreenUsesOuterGaps: Bool
        var outer: OuterGaps
    }

    struct OuterGaps: Codable, Equatable {
        var left: Double
        var right: Double
        var top: Double
        var bottom: Double
    }

    struct Niri: Codable, Equatable {
        var visibleContainerCount: Int
        var infiniteLoop: Bool
        var centerFocusedColumn: CenterFocusedColumn
        var alwaysCenterSingleColumn: Bool
        var singleWindowFit: SingleWindowFit
        var containerPrimarySpanPresets: [Double]?
        var defaultContainerPrimarySpan: Double?
    }

    struct Dwindle: Codable, Equatable {
        var smartSplit: Bool
        var defaultSplitRatio: Double
        var splitWidthMultiplier: Double
        var singleWindowFit: SingleWindowFit
        var useGlobalGaps: Bool
        var moveToRootStable: Bool
        var moveGroupsWindows: Bool? = false
    }

    struct Gestures: Codable, Equatable {
        var scrollEnabled: Bool
        var scrollSensitivity: Double
        var scrollModifierKey: ScrollModifierKey
        var mouseMoveModifierKey: MouseMoveModifierKey
        var mouseResizeModifierKey: MouseResizeModifierKey
        var fingerCount: GestureFingerCount
        var invertDirection: Bool
        var trackpadScrollStyle: TrackpadScrollStyle
        var workspaceSwipeEnabled: Bool
        var workspaceSwipeFingerCount: GestureFingerCount
        var workspaceSwipeAxis: WorkspaceSwipeAxis
        var windowMoveEnabled: Bool? = false
        var windowMoveFingerCount: GestureFingerCount? = .four
        var windowResizeEnabled: Bool? = false
        var windowResizeFingerCount: GestureFingerCount? = .three
        var windowGestureSensitivity: Double? = 1.0
    }
}

// MARK: - Defaults & Diffing

extension SettingsExport {
    static func defaults() -> SettingsExport {
        SettingsExport(
            hotkeysEnabled: true,
            focus: Focus.defaults(),
            mouseWarp: MouseWarp.defaults(),
            routing: Routing.defaults(),
            monitorRanking: [],
            gaps: Gaps.defaults(),
            niri: Niri.defaults(),
            workspaceConfigurations: BuiltInSettingsDefaults.workspaceConfigurations,
            defaultLayoutType: .niri,
            hotkeyBindings: HotkeyBindingRegistry.defaults(),
            systemHyperTrigger: .default,
            hyperKeyModifiers: .default,
            appRules: BuiltInSettingsDefaults.appRules,
            monitorOrientationSettings: [],
            monitorNiriSettings: [],
            dwindle: Dwindle.defaults(),
            monitorDwindleSettings: [],
            monitorGapSettings: [],
            preventSleepEnabled: false,
            ipcEnabled: true,
            gestures: Gestures.defaults(),
            animationsEnabled: true,
            animationStyle: .snappy,
            appearanceMode: .dark,
            tabRailAppIcons: false
        )
    }
}

extension SettingsExport.Focus {
    static func defaults() -> Self {
        Self(
            followsMouse: false,
            raiseOnMouseFocus: false,
            lockModifier: .off,
            moveMouseToFocusedWindow: false,
            followsWindowToMonitor: false,
            crossesMonitorAtEdge: false,
            moveCrossesMonitorAtEdge: false
        )
    }
}

extension SettingsExport.MouseWarp {
    static func defaults() -> Self {
        Self(
            margin: 1,
            enabled: true,
            constrainToArrangement: false
        )
    }
}

extension SettingsExport.Routing {
    static func defaults() -> Self {
        Self(
            mode: .macOS,
            arrangements: []
        )
    }
}

extension SettingsExport.Gaps {
    static func defaults() -> Self {
        Self(
            size: 16,
            fullscreenUsesOuterGaps: false,
            outer: SettingsExport.OuterGaps(left: 8, right: 8, top: 8, bottom: 8)
        )
    }
}

extension SettingsExport.Niri {
    static func defaults() -> Self {
        Self(
            visibleContainerCount: 2,
            infiniteLoop: false,
            centerFocusedColumn: .never,
            alwaysCenterSingleColumn: false,
            singleWindowFit: .gapped,
            containerPrimarySpanPresets: BuiltInSettingsDefaults.niriContainerPrimarySpanPresets,
            defaultContainerPrimarySpan: 0.5
        )
    }
}

extension SettingsExport.Dwindle {
    static func defaults() -> Self {
        Self(
            smartSplit: false,
            defaultSplitRatio: 1.0,
            splitWidthMultiplier: 1.0,
            singleWindowFit: .gapped,
            useGlobalGaps: true,
            moveToRootStable: true,
            moveGroupsWindows: false
        )
    }
}

extension SettingsExport.Gestures {
    static func defaults() -> Self {
        Self(
            scrollEnabled: true,
            scrollSensitivity: 5.0,
            scrollModifierKey: .optionShift,
            mouseMoveModifierKey: .option,
            mouseResizeModifierKey: .option,
            fingerCount: .three,
            invertDirection: true,
            trackpadScrollStyle: .snap,
            workspaceSwipeEnabled: false,
            workspaceSwipeFingerCount: .three,
            workspaceSwipeAxis: .vertical
        )
    }
}
