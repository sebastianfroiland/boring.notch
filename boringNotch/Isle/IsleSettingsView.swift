//
//  IsleSettingsView.swift
//  boringNotch
//
//  Settings pane for the Isle additions.
//  Licensed under GPL-3.0 like the rest of the project.
//

import Defaults
import SwiftUI

struct IsleSettings: View {
    @Default(.isleMenuBarShield) private var menuBarShield
    @Default(.isleMenuBarShieldClearance) private var clearance
    @Default(.isleCalendarLeadMinutes) private var leadMinutes
    @Default(.openNotchOnHover) private var openNotchOnHover
    @Default(.minimumHoverDuration) private var minimumHoverDuration

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .isleLiquidGlass) {
                    Text("Liquid Glass when open")
                }
                .disabled(!IsleGlass.isSupported)
                Defaults.Toggle(key: .isleAlbumGlow) {
                    Text("Glow from album color")
                }
                Defaults.Toggle(key: .isleBlurTransition) {
                    Text("Blur and scale when opening")
                }
            } header: {
                Text("Appearance")
            } footer: {
                Text(IsleGlass.isSupported
                     ? "The closed island stays solid black so it blends with the notch."
                     : "Liquid Glass needs macOS 26 or later. The island stays black on this Mac.")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }

            Section {
                Defaults.Toggle(key: .isleHoverPeek) {
                    Text("Peek on hover")
                }
                if openNotchOnHover {
                    Slider(value: $minimumHoverDuration, in: 0...1.5, step: 0.05) {
                        HStack {
                            Text("Open delay")
                            Spacer()
                            Text("\(minimumHoverDuration, specifier: "%.2f")s")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("Hover")
            } footer: {
                Text("The island grows slightly while the pointer rests on it. A click always opens it immediately.")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }

            Section {
                Defaults.Toggle(key: .isleMenuBarShield) {
                    Text("Keep the menu bar hidden in full screen")
                }
                if menuBarShield {
                    Defaults.Toggle(key: .isleMenuBarShieldFullWidth) {
                        Text("Shield the whole top edge")
                    }
                    Slider(value: $clearance, in: 2...12, step: 1) {
                        HStack {
                            Text("Distance from edge")
                            Spacer()
                            Text("\(Int(clearance)) pt")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("Menu bar shield")
            } footer: {
                Text("Stops the pointer a few points below the top edge above the island so the hidden menu bar does not slide down. Hold ⌘, ⌥ or fn, or keep pushing upward for a second, to reach the menu bar. Needs Accessibility permission.")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }

            Section {
                Defaults.Toggle(key: .isleCalendarAlerts) {
                    Text("Calendar alerts")
                }
                Stepper(value: $leadMinutes, in: 1...60) {
                    HStack {
                        Text("Alert before start")
                        Spacer()
                        Text("\(leadMinutes) min")
                            .foregroundStyle(.secondary)
                    }
                }
                Defaults.Toggle(key: .isleTimerEnabled) {
                    Text("Timer")
                }
                Defaults.Toggle(key: .isleBluetoothActivity) {
                    Text("AirPods and Bluetooth devices")
                }
                Defaults.Toggle(key: .isleLowBatteryAlerts) {
                    Text("Low battery at 20, 10 and 5 %")
                }
                Defaults.Toggle(key: .isleBrightnessHUD) {
                    Text("Brightness HUD for manual changes")
                }
            } header: {
                Text("Live activities")
            } footer: {
                Text("Calendar alerts use the calendars selected under Calendar. The brightness HUD ignores auto-brightness (only jumps of 3 % or more).")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
        }
        .navigationTitle("Island")
    }
}
