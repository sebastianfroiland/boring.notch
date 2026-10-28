//
//  IsleServices.swift
//  boringNotch
//
//  Starts and stops the Isle monitors together with the app.
//  Licensed under GPL-3.0 like the rest of the project.
//

import Combine
import Defaults
import Foundation

@MainActor
enum IsleServices {
    private static var cancellables: Set<AnyCancellable> = []

    static func start() {
        guard cancellables.isEmpty else { return }

        follow(.isleCalendarAlerts, start: { CalendarAlertMonitor.shared.start() }, stop: { CalendarAlertMonitor.shared.stop() })
        follow(.isleLowBatteryAlerts, start: { LowBatteryMonitor.shared.start() }, stop: { LowBatteryMonitor.shared.stop() })
        follow(.isleBrightnessHUD, start: { BrightnessChangeMonitor.shared.start() }, stop: { BrightnessChangeMonitor.shared.stop() })
        follow(.isleBluetoothActivity, start: { BluetoothActivityMonitor.shared.start() }, stop: { BluetoothActivityMonitor.shared.stop() })
        Defaults.publisher(.isleTimerEnabled)
            .map(\.newValue)
            .removeDuplicates()
            .sink { enabled in
                if !enabled {
                    IsleTimerManager.shared.cancel()
                    if BoringViewCoordinator.shared.currentView == .timer {
                        BoringViewCoordinator.shared.currentView = .home
                    }
                }
            }
            .store(in: &cancellables)

        MenuBarShield.shared.bootstrap()
    }

    static func stop() {
        cancellables.removeAll()
        MenuBarShield.shared.stop()
        CalendarAlertMonitor.shared.stop()
        LowBatteryMonitor.shared.stop()
        BrightnessChangeMonitor.shared.stop()
        BluetoothActivityMonitor.shared.stop()
    }

    private static func follow(_ key: Defaults.Key<Bool>, start: @escaping () -> Void, stop: @escaping () -> Void) {
        Defaults.publisher(key)
            .map(\.newValue)
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { enabled in
                if enabled { start() } else { stop() }
            }
            .store(in: &cancellables)
    }
}
