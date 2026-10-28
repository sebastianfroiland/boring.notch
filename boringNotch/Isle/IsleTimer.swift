//
//  IsleTimer.swift
//  boringNotch
//
//  Countdown timer with a ring in the closed notch and its own tab.
//  Licensed under GPL-3.0 like the rest of the project.
//

import AppKit
import Combine
import Defaults
import SwiftUI

@MainActor
final class IsleTimerManager: ObservableObject {
    static let shared = IsleTimerManager()

    enum State: Equatable {
        case idle
        case running
        case paused
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var duration: TimeInterval = Defaults[.isleTimerLastDuration]
    @Published private(set) var endDate: Date?
    @Published private(set) var pausedRemaining: TimeInterval = 0

    private var finishTask: Task<Void, Never>?

    nonisolated static let presets: [TimeInterval] = [60, 3 * 60, 5 * 60, 10 * 60, 15 * 60, 25 * 60]

    private init() {}

    var isActive: Bool { state != .idle }

    func remaining(at date: Date = .now) -> TimeInterval {
        switch state {
        case .idle: return duration
        case .paused: return pausedRemaining
        case .running: return max(0, (endDate ?? date).timeIntervalSince(date))
        }
    }

    /// Fraction of the timer that is left (1 → 0).
    func fractionRemaining(at date: Date = .now) -> Double {
        guard duration > 0 else { return 0 }
        return max(0, min(1, remaining(at: date) / duration))
    }

    func start(duration newDuration: TimeInterval? = nil) {
        if let newDuration { duration = max(1, newDuration) }
        Defaults[.isleTimerLastDuration] = duration
        endDate = Date().addingTimeInterval(duration)
        state = .running
        IsleActivityCenter.shared.clear(kind: .timerDone)
        scheduleFinish()
    }

    func pause() {
        guard state == .running else { return }
        pausedRemaining = remaining()
        endDate = nil
        state = .paused
        finishTask?.cancel()
    }

    func resume() {
        guard state == .paused else { return }
        endDate = Date().addingTimeInterval(pausedRemaining)
        state = .running
        scheduleFinish()
    }

    func togglePause() {
        switch state {
        case .running: pause()
        case .paused: resume()
        case .idle: start()
        }
    }

    func cancel() {
        finishTask?.cancel()
        endDate = nil
        pausedRemaining = 0
        state = .idle
    }

    func add(seconds: TimeInterval) {
        switch state {
        case .idle:
            duration = max(60, duration + seconds)
            Defaults[.isleTimerLastDuration] = duration
        case .running:
            let newRemaining = max(1, remaining() + seconds)
            endDate = Date().addingTimeInterval(newRemaining)
            duration = max(duration, newRemaining)
            scheduleFinish()
        case .paused:
            pausedRemaining = max(1, pausedRemaining + seconds)
            duration = max(duration, pausedRemaining)
        }
    }

    private func scheduleFinish() {
        finishTask?.cancel()
        guard let endDate else { return }
        finishTask = Task { [weak self] in
            let delay = max(0, endDate.timeIntervalSinceNow)
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.finish()
        }
    }

    private func finish() {
        guard state == .running else { return }
        state = .idle
        endDate = nil
        NSSound(named: NSSound.Name("Glass"))?.play()
        IsleActivityCenter.shared.post(
            IsleActivity(
                kind: .timerDone,
                icon: "timer",
                tint: .orange,
                title: "Timer done",
                trailingText: Self.format(duration),
                duration: 6
            )
        )
    }

    nonisolated static func format(_ interval: TimeInterval) -> String {
        let total = Int(interval.rounded(.up))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Closed notch

/// Ring on the left of the notch, remaining time on the right.
struct IsleTimerLiveActivity: View {
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject var timer = IsleTimerManager.shared

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let tint: Color = timer.state == .paused ? .gray : .orange
            HStack(spacing: 0) {
                IsleRing(progress: timer.fractionRemaining(at: context.date), tint: tint, lineWidth: 2.5)
                    .frame(
                        width: max(0, vm.effectiveClosedNotchHeight - 14),
                        height: max(0, vm.effectiveClosedNotchHeight - 14)
                    )
                    .padding(.leading, 6)
                    .frame(width: max(0, vm.effectiveClosedNotchHeight - 4), alignment: .leading)

                Rectangle()
                    .fill(.black)
                    .frame(width: vm.closedNotchSize.width - cornerRadiusInsets.closed.top)

                Text(IsleTimerManager.format(timer.remaining(at: context.date)))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.trailing, 6)
            }
            .frame(height: vm.effectiveClosedNotchHeight, alignment: .center)
        }
    }
}

// MARK: - Tab

struct IsleTimerView: View {
    @ObservedObject var timer = IsleTimerManager.shared

    var body: some View {
        HStack(alignment: .center, spacing: 22) {
            TimelineView(.periodic(from: .now, by: 0.25)) { context in
                ZStack {
                    IsleRing(
                        progress: timer.state == .idle ? 1 : timer.fractionRemaining(at: context.date),
                        tint: timer.state == .paused ? .gray : .orange,
                        lineWidth: 7
                    )
                    VStack(spacing: 2) {
                        Text(IsleTimerManager.format(timer.remaining(at: context.date)))
                            .font(.system(size: 24, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                        Text(statusLabel)
                            .font(.caption)
                            .foregroundStyle(.gray)
                    }
                }
                .frame(width: 118, height: 118)
            }

            VStack(alignment: .leading, spacing: 10) {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(64), spacing: 8), count: 3), spacing: 8) {
                    ForEach(IsleTimerManager.presets, id: \.self) { preset in
                        Button {
                            timer.start(duration: preset)
                        } label: {
                            Text("\(Int(preset / 60)) min")
                                .font(.system(size: 12, weight: .medium))
                                .frame(width: 64, height: 26)
                                .isleGlassCapsule()
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }

                HStack(spacing: 8) {
                    controlButton(icon: "minus", label: "−1 min") { timer.add(seconds: -60) }
                    controlButton(
                        icon: timer.state == .running ? "pause.fill" : "play.fill",
                        label: timer.state == .running ? "Pause" : "Start"
                    ) { timer.togglePause() }
                    controlButton(icon: "plus", label: "+1 min") { timer.add(seconds: 60) }
                    controlButton(icon: "xmark", label: "Cancel") { timer.cancel() }
                        .disabled(timer.state == .idle)
                        .opacity(timer.state == .idle ? 0.4 : 1)
                }
            }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 4)
    }

    private var statusLabel: String {
        switch timer.state {
        case .idle: return "Ready"
        case .running: return "Running"
        case .paused: return "Paused"
        }
    }

    private func controlButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 44, height: 30)
                .isleGlassCapsule()
        }
        .buttonStyle(PlainButtonStyle())
        .help(label)
    }
}
