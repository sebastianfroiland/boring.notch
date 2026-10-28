//
//  IsleSettings.swift
//  boringNotch
//
//  Settings for the "Isle" additions (Liquid Glass, menu bar shield,
//  extra live activities, hover peek and polish).
//  Licensed under GPL-3.0 like the rest of the project.
//

import Defaults
import Foundation

extension Defaults.Keys {
    // MARK: Appearance
    /// Use Liquid Glass for the open island on macOS 26+. Falls back to black on older systems.
    static let isleLiquidGlass = Key<Bool>("isleLiquidGlass", default: true)
    /// Black tint on the glass (0 = clear glass, 1 = black). 0.42 looked washed-out gray on a real Mac.
    static let isleGlassTint = Key<Double>("isleGlassTint", default: 0.72)
    /// Glow tinted by the current album art color around the open island.
    static let isleAlbumGlow = Key<Bool>("isleAlbumGlow", default: true)
    /// Blur + scale transition when the island opens.
    static let isleBlurTransition = Key<Bool>("isleBlurTransition", default: true)

    // MARK: Behavior
    /// Grow the closed island slightly while the pointer hovers it, before it opens.
    static let isleHoverPeek = Key<Bool>("isleHoverPeek", default: true)

    // MARK: Menu bar shield
    /// Keep the auto-hidden menu bar from sliding down in full screen when the pointer hits the top edge above the island.
    static let isleMenuBarShield = Key<Bool>("isleMenuBarShield", default: false)
    /// Shield the whole top edge instead of only the area above the island.
    static let isleMenuBarShieldFullWidth = Key<Bool>("isleMenuBarShieldFullWidth", default: false)
    /// Distance (pt) from the top edge the pointer is held at.
    static let isleMenuBarShieldClearance = Key<Double>("isleMenuBarShieldClearance", default: 6)

    // MARK: Live activities
    static let isleCalendarAlerts = Key<Bool>("isleCalendarAlerts", default: true)
    static let isleCalendarLeadMinutes = Key<Int>("isleCalendarLeadMinutes", default: 10)
    static let isleTimerEnabled = Key<Bool>("isleTimerEnabled", default: true)
    static let isleTimerLastDuration = Key<Double>("isleTimerLastDuration", default: 5 * 60)
    static let isleBluetoothActivity = Key<Bool>("isleBluetoothActivity", default: true)
    static let isleLowBatteryAlerts = Key<Bool>("isleLowBatteryAlerts", default: true)
    static let isleBrightnessHUD = Key<Bool>("isleBrightnessHUD", default: true)
}
