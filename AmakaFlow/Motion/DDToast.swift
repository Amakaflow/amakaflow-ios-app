//
//  DDToast.swift
//  AmakaFlow
//
//  AMA-2383 — DD Toast confirmation system. Top-center capsule; queue of one;
//  push morph never pre-claims success. Spec: design-handoff/MOTION.md §3
//  Reference: design-handoff/reference/screens-toast.jsx
//

import Combine
import SwiftUI
import UIKit

// MARK: - Model

enum DDToastKind: Equatable {
    case success
    case device
    case undo
    case error
}

struct DDToastEvent: Identifiable, Equatable {
    let id: UUID
    var kind: DDToastKind
    var text: String
    var sub: String?
    /// Trailing action label (e.g. "Undo"). Presence extends hold to 4s.
    var action: String?
    /// Phase-1 push: spinner + pending copy. Never auto-dismisses.
    var pending: Bool
    /// Invoked when the trailing action is tapped (not part of Equatable).
    var onAction: (() -> Void)?

    init(
        id: UUID = UUID(),
        kind: DDToastKind,
        text: String,
        sub: String? = nil,
        action: String? = nil,
        pending: Bool = false,
        onAction: (() -> Void)? = nil
    ) {
        self.id = id
        self.kind = kind
        self.text = text
        self.sub = sub
        self.action = action
        self.pending = pending
        self.onAction = onAction
    }

    static func == (lhs: DDToastEvent, rhs: DDToastEvent) -> Bool {
        lhs.id == rhs.id
            && lhs.kind == rhs.kind
            && lhs.text == rhs.text
            && lhs.sub == rhs.sub
            && lhs.action == rhs.action
            && lhs.pending == rhs.pending
    }
}

// MARK: - Center (event bus)

@MainActor
final class DDToastCenter: ObservableObject {
    static let shared = DDToastCenter()

    @Published private(set) var current: DDToastEvent?
    private var queue: [DDToastEvent] = []
    private var dismissTask: Task<Void, Never>?

    /// Enqueue a toast. If one is visible, it waits (no stacking).
    func present(_ event: DDToastEvent) {
        if current == nil {
            show(event)
        } else {
            queue.append(event)
        }
    }

    /// Convenience: success confirmation.
    func success(_ text: String, sub: String? = nil) {
        present(DDToastEvent(kind: .success, text: text, sub: sub))
    }

    /// Convenience: error / failure confirmation.
    func error(_ text: String, sub: String? = nil) {
        present(DDToastEvent(kind: .error, text: text, sub: sub))
    }

    /// Convenience: device confirmation (Garmin / Apple Watch).
    func device(_ text: String, sub: String? = nil) {
        present(DDToastEvent(kind: .device, text: text, sub: sub))
    }

    /// Convenience: undoable confirmation (4s hold).
    func undo(_ text: String, sub: String? = nil, onUndo: @escaping () -> Void) {
        present(DDToastEvent(
            kind: .undo,
            text: text,
            sub: sub,
            action: DDToastCopy.undoAction,
            onAction: onUndo
        ))
    }

    /// Start a two-phase push morph. Returns the id so the caller can resolve.
    @discardableResult
    func beginPending(text: String, kind: DDToastKind = .device) -> UUID {
        let event = DDToastEvent(kind: kind, text: text, pending: true)
        present(event)
        return event.id
    }

    /// Morph the pending toast in place to its resolved state (or error).
    /// Pending toasts never auto-dismiss; resolve starts the hold+out cycle.
    func resolve(
        id: UUID,
        kind: DDToastKind,
        text: String,
        sub: String? = nil
    ) {
        if var current, current.id == id, current.pending {
            current.kind = kind
            current.text = text
            current.sub = sub
            current.pending = false
            self.current = current
            scheduleAutoDismiss(for: current)
            announceIfNeeded(current)
            return
        }
        if let index = queue.firstIndex(where: { $0.id == id && $0.pending }) {
            var queued = queue[index]
            queued.kind = kind
            queued.text = text
            queued.sub = sub
            queued.pending = false
            queue[index] = queued
            return
        }
        // Not currently showing / queued — present as a fresh resolved toast.
        present(DDToastEvent(kind: kind, text: text, sub: sub, pending: false))
    }

    func dismissCurrent() {
        dismissTask?.cancel()
        dismissTask = nil
        current = nil
        dequeueNext()
    }

    // MARK: Private

    private func show(_ event: DDToastEvent) {
        current = event
        if !event.pending {
            scheduleAutoDismiss(for: event)
            announceIfNeeded(event)
        }
    }

    private func scheduleAutoDismiss(for event: DDToastEvent) {
        dismissTask?.cancel()
        let hold = event.action == nil ? MotionTokens.toastHold : MotionTokens.toastHoldWithAction
        let out = MotionTokens.toastOut
        let id = event.id
        dismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64((hold + out) * 1_000_000_000))
            guard !Task.isCancelled else { return }
            guard current?.id == id else { return }
            current = nil
            dequeueNext()
        }
    }

    private func dequeueNext() {
        guard current == nil, !queue.isEmpty else { return }
        show(queue.removeFirst())
    }

    private func announceIfNeeded(_ event: DDToastEvent) {
        guard !event.pending else { return }
        var announcement = event.text
        if let sub = event.sub, !sub.isEmpty {
            announcement += ". \(sub)"
        }
        UIAccessibility.post(notification: .announcement, argument: announcement)
    }
}

// MARK: - Copy (copy-lock)

enum DDToastCopy {
    static let undoAction = "Undo"
    static let savedToLibrary = "Saved to Library"
    static let sentToGarmin = "Sent to Garmin"
    static let sendingToGarmin = "Sending to Garmin…"
    static let garminWidgetSub = "OPEN THE AMAKAFLOW WIDGET TO DOWNLOAD"
    static let onAppleWatch = "On your Apple Watch"
    static let scheduling = "Scheduling…"
    static let removedFromWatch = "Removed from watch"
    static let libraryUntouched = "LIBRARY UNTOUCHED"

    static func savedSub(workoutName: String, minutes: Int, collection: String) -> String {
        "\(workoutName.uppercased()) — \(minutes) · IN \(collection.uppercased())"
    }

    static func appleWatchSub(steps: Int, slotsFree: Int) -> String {
        "WORKOUT APP · \(steps) STEPS · \(slotsFree) SLOTS FREE"
    }
}

// MARK: - Host + capsule

struct DDToastHost: View {
    @ObservedObject var center: DDToastCenter
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack {
            if let toast = center.current {
                DDToastCapsule(toast: toast, reduceMotion: reduceMotion) {
                    toast.onAction?()
                    center.dismissCurrent()
                }
                .padding(.top, MotionTokens.toastTopInset)
                .transition(toastTransition)
                .accessibilityIdentifier("dd_toast")
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // Only the capsule (and its Undo action) intercepts hits; the rest of
        // the overlay is pass-through.
        .allowsHitTesting(center.current != nil)
        .animation(
            reduceMotion ? .easeOut(duration: MotionTokens.fast) : MotionTokens.toastSpring,
            value: center.current?.id
        )
    }

    private var toastTransition: AnyTransition {
        if reduceMotion {
            return .opacity
        }
        return .asymmetric(
            insertion: .modifier(
                active: ToastOffsetOpacity(offsetY: MotionTokens.toastInOffsetY, opacity: 0),
                identity: ToastOffsetOpacity(offsetY: 0, opacity: 1)
            ),
            removal: .modifier(
                active: ToastOffsetOpacity(offsetY: MotionTokens.toastOutOffsetY, opacity: 0),
                identity: ToastOffsetOpacity(offsetY: 0, opacity: 1)
            )
        )
    }
}

private struct ToastOffsetOpacity: ViewModifier {
    let offsetY: CGFloat
    let opacity: Double
    func body(content: Content) -> some View {
        content.offset(y: offsetY).opacity(opacity)
    }
}

struct DDToastCapsule: View {
    let toast: DDToastEvent
    var reduceMotion: Bool = false
    var onAction: (() -> Void)?

    var body: some View {
        HStack(spacing: 10) {
            iconChip
            VStack(alignment: .leading, spacing: 1) {
                Text(toast.text)
                    .ddDisplayText(13, weight: .bold)
                    .foregroundColor(DailyDriver.foreground)
                    .lineLimit(1)
                if let sub = toast.sub, !sub.isEmpty {
                    Text(sub)
                        .font(.system(size: 8, weight: .semibold, design: .monospaced))
                        .foregroundColor(DailyDriver.foregroundDim)
                        .lineLimit(1)
                }
            }
            .frame(minWidth: 0, maxWidth: 220, alignment: .leading)

            if let action = toast.action, !toast.pending {
                Button(
                    action: { onAction?() },
                    label: {
                        Text(action)
                            .ddDisplayText(12, weight: .bold)
                            .foregroundColor(DailyDriver.amber)
                    }
                )
                .buttonStyle(.plain)
                .accessibilityIdentifier("dd_toast_action")
            }
        }
        .padding(.leading, 10)
        .padding(.trailing, 16)
        .padding(.vertical, toast.sub == nil ? 8 : 9)
        .background(Color(red: 24 / 255, green: 24 / 255, blue: 27 / 255).opacity(0.97))
        .overlay(
            Capsule().stroke(DailyDriver.borderStrong, lineWidth: 1)
        )
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.5), radius: 17, y: 12)
        .padding(.horizontal, 16)
        .accessibilityElement(children: toast.action == nil || toast.pending ? .combine : .contain)
        .accessibilityAddTraits(.isStaticText)
    }

    @ViewBuilder
    private var iconChip: some View {
        ZStack {
            Circle()
                .fill(chipBackground)
                .frame(width: 26, height: 26)
            if toast.pending {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(DailyDriver.lime)
                    .scaleEffect(0.55)
            } else {
                Image(systemName: chipSymbol)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(chipForeground)
                    .scaleEffect(reduceMotion ? 1 : 1)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .accessibilityHidden(true)
    }

    private var chipBackground: Color {
        if toast.pending { return DailyDriver.card2 }
        switch toast.kind {
        case .undo: return DailyDriver.amber
        case .device: return DailyDriver.blue
        case .error: return DailyDriver.red
        case .success: return DailyDriver.lime
        }
    }

    private var chipForeground: Color {
        switch toast.kind {
        case .device: return .white
        default: return DailyDriver.ink
        }
    }

    private var chipSymbol: String {
        switch toast.kind {
        case .undo: return "xmark"
        case .device: return "applewatch"
        case .error: return "exclamationmark"
        case .success: return "checkmark"
        }
    }
}

// MARK: - Root overlay helper

extension View {
    /// Mount DD Toast at the app root. Call sites publish via `DDToastCenter.shared`.
    @MainActor
    func ddToastHost(_ center: DDToastCenter? = nil) -> some View {
        overlay {
            DDToastHost(center: center ?? .shared)
        }
    }
}
