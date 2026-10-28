//
//  IsleMonitors.swift
//  boringNotch
//
//  Background monitors that feed IsleActivityCenter / the HUD:
//  calendar alerts, low battery, and brightness changes not caused by auto-brightness.
//  Licensed under GPL-3.0 like the rest of the project.
//

import AppKit
import Combine
import Defaults
@preconcurrency import EventKit
import SwiftUI

// MARK: - Calendar alerts

/// Shows an alert N minutes (default 10) before an event and again when it starts.
@MainActor
final class CalendarAlertMonitor {
    static let shared = CalendarAlertMonitor()

    private let store = EKEventStore()
    private var timer: Timer?
    private var alerted: Set<String> = []
    private var storeObserver: Any?

    private init() {}

    func start() {
        guard timer == nil else { return }
        guard hasAccess else {
            // Calendar access is requested by the calendar settings / onboarding; retry later.
            scheduleTimer(interval: 60)
            return
        }
        storeObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: store, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.check() }
        }
        scheduleTimer(interval: 15)
        check()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if let storeObserver { NotificationCenter.default.removeObserver(storeObserver) }
        storeObserver = nil
    }

    private func scheduleTimer(interval: TimeInterval) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if self.storeObserver == nil {
                    // Was waiting for access.
                    if self.hasAccess {
                        self.stop()
                        self.start()
                    }
                } else {
                    self.check()
                }
            }
        }
        timer?.tolerance = 2
    }

    private var hasAccess: Bool {
        let status = EKEventStore.authorizationStatus(for: .event)
        if #available(macOS 14.0, *) {
            return status == .fullAccess
        }
        return status == .authorized
    }

    private var selectedCalendars: [EKCalendar]? {
        switch Defaults[.calendarSelectionState] {
        case .all:
            return nil
        case .selected(let ids):
            return store.calendars(for: .event).filter { ids.contains($0.calendarIdentifier) }
        }
    }

    func check(now: Date = Date()) {
        guard Defaults[.isleCalendarAlerts], hasAccess else { return }
        let lead = TimeInterval(max(1, Defaults[.isleCalendarLeadMinutes]) * 60)
        let calendars = selectedCalendars
        if let calendars, calendars.isEmpty { return }

        let predicate = store.predicateForEvents(
            withStart: now.addingTimeInterval(-90),
            end: now.addingTimeInterval(lead + 60),
            calendars: calendars
        )
        let events = store.events(matching: predicate)
            .filter { !$0.isAllDay && $0.status != .canceled }
            .sorted { $0.startDate < $1.startDate }

        for event in events {
            guard let start = event.startDate else { continue }
            let key = (event.calendarItemIdentifier) + "@\(start.timeIntervalSince1970)"
            let untilStart = start.timeIntervalSince(now)
            let title = (event.title?.isEmpty == false) ? event.title! : "Event"
            let tint = Color(nsColor: event.calendar?.color ?? .systemBlue)

            if untilStart > 0, untilStart <= lead, !alerted.contains(key + "#soon") {
                alerted.insert(key + "#soon")
                let minutes = Int((untilStart / 60).rounded(.up))
                IsleActivityCenter.shared.post(
                    IsleActivity(
                        kind: .calendar,
                        icon: "calendar",
                        tint: tint,
                        title: title,
                        trailingText: "in \(minutes) min",
                        duration: 6
                    )
                )
            } else if untilStart <= 0, untilStart > -75, !alerted.contains(key + "#now") {
                alerted.insert(key + "#now")
                alerted.insert(key + "#soon")
                IsleActivityCenter.shared.post(
                    IsleActivity(
                        kind: .calendar,
                        icon: "calendar.badge.clock",
                        tint: tint,
                        title: title,
                        trailingText: "Now",
                        duration: 8
                    )
                )
            }
        }

        if alerted.count > 500 { alerted.removeAll() }
    }
}

// MARK: - Low battery

/// Alerts once when the battery drops below 20 %, 10 % and 5 % while not charging.
@MainActor
final class LowBatteryMonitor {
    static let shared = LowBatteryMonitor()

    private let thresholds: [Float] = [20, 10, 5]
    private var lastLevel: Float?
    private var fired: Set<Float> = []
    private var cancellables: Set<AnyCancellable> = []

    private init() {}

    func start() {
        guard cancellables.isEmpty else { return }
        let model = BatteryStatusViewModel.shared
        model.$levelBattery
            .combineLatest(model.$isPluggedIn, model.$isCharging)
            .receive(on: RunLoop.main)
            .sink { [weak self] level, pluggedIn, charging in
                self?.update(level: level, onPower: pluggedIn || charging)
            }
            .store(in: &cancellables)
    }

    func stop() {
        cancellables.removeAll()
    }

    private func update(level: Float, onPower: Bool) {
        defer { lastLevel = level }
        guard level > 0 else { return }

        if onPower {
            fired.removeAll()
            IsleActivityCenter.shared.clear(kind: .lowBattery)
            return
        }
        // Re-arm thresholds we are above again (e.g. after charging while asleep).
        fired = fired.filter { level <= $0 }

        guard Defaults[.isleLowBatteryAlerts], let previous = lastLevel else { return }
        // Lowest threshold crossed in this step.
        guard let crossed = thresholds.filter({ previous > $0 && level <= $0 && !fired.contains($0) }).min() else {
            return
        }
        for threshold in thresholds where threshold >= crossed {
            fired.insert(threshold)
        }

        let tint: Color = crossed <= 10 ? .red : .orange
        IsleActivityCenter.shared.post(
            IsleActivity(
                kind: .lowBattery,
                icon: crossed <= 10 ? "battery.0percent" : "battery.25percent",
                tint: tint,
                title: "Low battery",
                trailingText: "\(Int(level)) %",
                progress: Double(level) / 100,
                duration: crossed <= 5 ? 8 : 5
            )
        )
    }
}

// MARK: - Brightness

/// Shows the brightness HUD for changes made outside the app (Control Center, other apps,
/// system keys when HUD replacement is off), but ignores the slow drift of auto-brightness:
/// only jumps of at least 0.03 between two samples count.
@MainActor
final class BrightnessChangeMonitor {
    static let shared = BrightnessChangeMonitor()

    static let minimumJump: Float = 0.03
    private let interval: TimeInterval = 0.4
    private var timer: Timer?
    private var lastSample: Float?
    private var polling = false
    private var failures = 0

    private init() {}

    func start() {
        guard timer == nil else { return }
        lastSample = nil
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.poll() }
        }
        timer?.tolerance = 0.1
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        lastSample = nil
    }

    private func poll() async {
        guard !polling, Defaults[.isleBrightnessHUD] else { return }
        polling = true
        defer { polling = false }

        guard let value = await XPCHelperClient.shared.currentScreenBrightness() else {
            // No internal display / DisplayServices unavailable: give up after a while.
            failures += 1
            if failures >= 25 { stop() }
            return
        }
        failures = 0
        defer { lastSample = value }
        guard let previous = lastSample else { return }
        guard abs(value - previous) >= Self.minimumJump else { return }

        // Our own key handling already shows the HUD.
        if Date().timeIntervalSince(BrightnessManager.shared.lastChangeAt) < 1.5 { return }

        BoringViewCoordinator.shared.toggleSneakPeek(
            status: true,
            type: .brightness,
            value: CGFloat(value),
            force: true
        )
    }
}
