//
//  IsleActivity.swift
//  boringNotch
//
//  A small queue of transient live activities (calendar alerts, Bluetooth
//  connections, low battery, timer finished) shown around the closed notch.
//  Licensed under GPL-3.0 like the rest of the project.
//

import Combine
import SwiftUI

struct IsleActivity: Identifiable, Equatable {
    enum Kind: Equatable {
        case calendar
        case bluetooth
        case lowBattery
        case timerDone
    }

    let id = UUID()
    var kind: Kind
    var icon: String
    var tint: Color
    var title: String
    var trailingText: String? = nil
    /// When set (0...1), a ring is drawn on the trailing side.
    var progress: Double? = nil
    var duration: TimeInterval = 4
}

@MainActor
final class IsleActivityCenter: ObservableObject {
    static let shared = IsleActivityCenter()

    @Published private(set) var current: IsleActivity?

    private var queue: [IsleActivity] = []
    private var hideTask: Task<Void, Never>?
    private let maxQueued = 4

    private init() {}

    func post(_ activity: IsleActivity) {
        // Replace an identical pending activity instead of stacking duplicates.
        queue.removeAll { $0.kind == activity.kind && $0.title == activity.title }
        if current == nil {
            show(activity)
        } else if current?.kind == activity.kind && current?.title == activity.title {
            show(activity)
        } else {
            queue.append(activity)
            if queue.count > maxQueued { queue.removeFirst(queue.count - maxQueued) }
        }
    }

    func dismissCurrent() {
        hideTask?.cancel()
        withAnimation(.smooth) { current = nil }
        showNextAfterDelay()
    }

    func clear(kind: IsleActivity.Kind) {
        queue.removeAll { $0.kind == kind }
        if current?.kind == kind { dismissCurrent() }
    }

    private func show(_ activity: IsleActivity) {
        hideTask?.cancel()
        withAnimation(.spring(response: 0.42, dampingFraction: 0.8)) {
            current = activity
        }
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(activity.duration))
            guard !Task.isCancelled else { return }
            self?.dismissCurrent()
        }
    }

    private func showNextAfterDelay() {
        guard !queue.isEmpty else { return }
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(450))
            guard let self, self.current == nil, !self.queue.isEmpty else { return }
            self.show(self.queue.removeFirst())
        }
    }
}

// MARK: - Closed-notch view

/// Wide "ears" layout: content on the left and right of the hardware notch.
struct IsleActivityView: View {
    @EnvironmentObject var vm: BoringViewModel
    let activity: IsleActivity

    private let sideWidth: CGFloat = 150

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: activity.icon)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(activity.tint)
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 18)
                MarqueeText(
                    .constant(activity.title),
                    font: .subheadline,
                    nsFont: .subheadline,
                    textColor: .white,
                    minDuration: 1,
                    frameWidth: sideWidth - 30
                )
            }
            .padding(.leading, 6)
            .frame(width: sideWidth, alignment: .leading)

            Rectangle()
                .fill(.black)
                .frame(width: vm.closedNotchSize.width + 10)

            HStack(spacing: 6) {
                if let text = activity.trailingText {
                    Text(text)
                        .font(.subheadline.weight(.medium))
                        .monospacedDigit()
                        .foregroundStyle(activity.tint)
                        .lineLimit(1)
                }
                if let progress = activity.progress {
                    IsleRing(progress: progress, tint: activity.tint)
                        .frame(width: 16, height: 16)
                }
            }
            .padding(.trailing, 8)
            .frame(width: sideWidth, alignment: .trailing)
        }
        .frame(height: vm.effectiveClosedNotchHeight, alignment: .center)
        .transition(.blurReplace)
    }
}

struct IsleRing: View {
    var progress: Double
    var tint: Color
    var lineWidth: CGFloat = 3

    var body: some View {
        ZStack {
            Circle()
                .stroke(tint.opacity(0.25), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0, min(1, progress)))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .animation(.linear(duration: 0.25), value: progress)
    }
}
