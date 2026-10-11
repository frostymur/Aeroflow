// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2026 BarutSRB — https://github.com/OmniNull/OmniWM
// Copyright (C) 2026 Timur Iskakov — https://github.com/frostymur

import AeroFlow
import AppKit

@main
@MainActor
enum AeroFlowApp {
    static func main() {
        let bootstrap = AppBootstrapState()
        AppDelegate.sharedBootstrap = bootstrap
        let app = NSApplication.shared
        // Strong local: NSApplication.delegate does not retain its value,
        // so the delegate must outlive app.run().
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
