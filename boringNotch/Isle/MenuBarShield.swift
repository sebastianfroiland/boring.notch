//
//  MenuBarShield.swift
//  boringNotch
//
//  Keeps the auto-hidden menu bar of a full-screen app from sliding down when the
//  pointer hits the top edge above the island.
//
//  How: the reveal is driven by mouse-moved events that reach the top few points of
//  the display. A CGEventTap at the HID level rewrites the y location of mouse-moved /
//  dragged events in that zone so the pointer stops `clearance` pt below the edge
//  (same technique as fkmenu / menu-bar-gate). Warping the cursor and
//  CGAssociateMouseAndMouseCursorPosition are deliberately NOT used: only the upward
//  y-coordinate is limited, so the pointer can always move sideways/down and can never
//  get stuck.
//
//  Fail-safes:
//   - The tap is only enabled while a full-screen space is showing (idle otherwise).
//   - Holding ⌘, ⌥ or fn bypasses the shield.
//   - Pushing against the edge for ~1 s lets the menu bar through for 3 s.
//   - Re-enabled when macOS disables the tap for timeout; torn down on sleep, lock,
//     setting off and app termination.
//
//  Requires Accessibility permission.
//  Licensed under GPL-3.0 like the rest of the project.
//

import AppKit
import ApplicationServices
import Combine
import Defaults

@MainActor
final class MenuBarShield {
    static let shared = MenuBarShield()

    private struct Zone {
        let minX: CGFloat
        let maxX: CGFloat
        /// Top edge of the display in global CG coordinates (y grows downward).
        let top: CGFloat
    }

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var zones: [Zone] = []
    private var tapEnabled = false
    private var clearance: CGFloat = 6
    private var cancellables: Set<AnyCancellable> = []
    private var observers: [NSObjectProtocol] = []
    private var workspaceObservers: [NSObjectProtocol] = []
    private var refreshTimer: Timer?

    // Push-through escape hatch.
    private var pushStartedAt: Date?
    private var pushDistance: CGFloat = 0
    private var bypassUntil: Date = .distantPast
    private let pushDuration: TimeInterval = 1.0
    private let pushThreshold: CGFloat = 120
    private let bypassDuration: TimeInterval = 3

    private init() {}

    // MARK: - Lifecycle

    /// Called once at launch. Follows the setting from then on.
    func bootstrap() {
        guard cancellables.isEmpty else { return }
        Defaults.publisher(.isleMenuBarShield)
            .map(\.newValue)
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] enabled in
                Task { @MainActor in
                    if enabled { await self?.start(prompt: true) } else { self?.stop() }
                }
            }
            .store(in: &cancellables)

        FullscreenMediaDetector.shared.$anyFullscreenStatus
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshZones() }
            .store(in: &cancellables)

        observers.append(
            NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.refreshZones() }
            }
        )
        observers.append(
            NotificationCenter.default.addObserver(
                forName: .accessibilityAuthorizationChanged, object: nil, queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    if Defaults[.isleMenuBarShield] { await self?.start(prompt: false) }
                }
            }
        )

        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            workspaceObservers.append(
                workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    Task { @MainActor in self?.stop() }
                }
            )
        }
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification, NSWorkspace.activeSpaceDidChangeNotification] {
            workspaceObservers.append(
                workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    Task { @MainActor in
                        if Defaults[.isleMenuBarShield] { await self?.start(prompt: false) }
                        self?.refreshZones()
                    }
                }
            )
        }
    }

    func start(prompt: Bool) async {
        guard Defaults[.isleMenuBarShield] else { return }
        if tap == nil {
            let trusted: Bool
            if prompt {
                trusted = await XPCHelperClient.shared.ensureAccessibilityAuthorization(promptIfNeeded: true)
            } else {
                trusted = await XPCHelperClient.shared.isAccessibilityAuthorized()
            }
            guard trusted, Defaults[.isleMenuBarShield], tap == nil else { return }
            createTap()
        }
        refreshZones()
        if refreshTimer == nil {
            // Space changes are not always reported promptly; keep the zones fresh cheaply.
            refreshTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.refreshZones() }
            }
            refreshTimer?.tolerance = 0.5
        }
    }

    /// Tears everything down. Safe to call any number of times (also from applicationWillTerminate).
    func stop() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        tap = nil
        runLoopSource = nil
        tapEnabled = false
        zones = []
        resetPush()
        // Never leave the pointer detached, even though the shield itself does not detach it.
        CGAssociateMouseAndMouseCursorPosition(1)
    }

    // MARK: - Tap

    private func createTap() {
        let types: [CGEventType] = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << CGEventMask($1.rawValue)) }

        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let shield = Unmanaged<MenuBarShield>.fromOpaque(userInfo).takeUnretainedValue()
                // The run loop source is attached to the main run loop.
                var result: Unmanaged<CGEvent>? = Unmanaged.passUnretained(event)
                MainActor.assumeIsolated { result = shield.handle(type: type, event: event) }
                return result
            },
            userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        ) else {
            NSLog("MenuBarShield: could not create event tap (Accessibility permission missing?)")
            return
        }
        self.tap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        // Stays disabled until a full-screen space shows up (see refreshZones).
        CGEvent.tapEnable(tap: tap, enable: false)
        tapEnabled = false
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap, tapEnabled { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        guard tapEnabled, !zones.isEmpty else { return Unmanaged.passUnretained(event) }

        let flags = event.flags
        if flags.contains(.maskCommand) || flags.contains(.maskAlternate) || flags.contains(.maskSecondaryFn) {
            resetPush()
            return Unmanaged.passUnretained(event)
        }
        if Date() < bypassUntil { return Unmanaged.passUnretained(event) }

        var location = event.location

        guard let zone = zones.first(where: { location.x >= $0.minX && location.x <= $0.maxX && location.y < $0.top + clearance && location.y > $0.top - 2 })
        else {
            resetPush()
            return Unmanaged.passUnretained(event)
        }

        // Escape hatch: deliberately pushing against the edge lets the menu bar through.
        let deltaY = CGFloat(event.getDoubleValueField(.mouseEventDeltaY))
        if deltaY < 0 {
            let now = Date()
            if pushStartedAt == nil { pushStartedAt = now }
            pushDistance += -deltaY
            if let started = pushStartedAt, now.timeIntervalSince(started) >= pushDuration, pushDistance >= pushThreshold {
                bypassUntil = now.addingTimeInterval(bypassDuration)
                resetPush()
                return Unmanaged.passUnretained(event)
            }
        } else if deltaY > 0 {
            resetPush()
        }

        location.y = zone.top + clearance
        event.location = location
        return Unmanaged.passUnretained(event)
    }

    private func resetPush() {
        pushStartedAt = nil
        pushDistance = 0
    }

    // MARK: - Zones

    /// Recomputes where the shield applies. Runs on the main thread (same run loop as the tap).
    private func refreshZones() {
        guard let tap else {
            zones = []
            return
        }
        let fullscreen = FullscreenMediaDetector.shared.anyFullscreenStatus
        clearance = CGFloat(max(1, min(24, Defaults[.isleMenuBarShieldClearance])))
        let screens = NSScreen.screens
        guard let primaryHeight = screens.first?.frame.maxY else { return }

        var newZones: [Zone] = []
        for screen in screens {
            guard let uuid = screen.displayUUID, fullscreen[uuid] == true else { continue }
            let frame = screen.frame
            // If another display sits directly above, the top edge is a passage, not an edge.
            let hasScreenAbove = screens.contains { other in
                other != screen && abs(other.frame.minY - frame.maxY) < 1
                    && other.frame.maxX > frame.minX && other.frame.minX < frame.maxX
            }
            if hasScreenAbove { continue }

            let top = primaryHeight - frame.maxY
            if Defaults[.isleMenuBarShieldFullWidth] {
                newZones.append(Zone(minX: frame.minX, maxX: frame.maxX, top: top))
            } else {
                let width = openNotchSize.width + 48
                newZones.append(Zone(minX: frame.midX - width / 2, maxX: frame.midX + width / 2, top: top))
            }
        }
        zones = newZones

        let shouldEnable = Defaults[.isleMenuBarShield] && !newZones.isEmpty
        if shouldEnable != tapEnabled {
            CGEvent.tapEnable(tap: tap, enable: shouldEnable)
            tapEnabled = shouldEnable
            if !shouldEnable { resetPush() }
        }
    }
}
