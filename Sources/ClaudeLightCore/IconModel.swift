import Foundation

public enum IconLamp: String, Sendable, Equatable {
    case red, orange, green, off
}

public struct IconState: Sendable, Equatable {
    public let lamp: IconLamp
    public let blink: Bool
    public let breathe: Bool
    public init(lamp: IconLamp, blink: Bool, breathe: Bool) {
        self.lamp = lamp
        self.blink = blink
        self.breathe = breathe
    }
}

/// Aggregate lamp for the menu-bar icon. Priority: red (needs you) > orange
/// (working) > green (idle) > off (no live sessions). Pass the LIVE sessions.
public func iconState(for sessions: [Session]) -> IconState {
    if sessions.isEmpty {
        return IconState(lamp: .off, blink: false, breathe: false)
    }
    let hasAttention = sessions.contains { $0.status == .attention }
    let hasWaiting = sessions.contains { $0.status == .waiting }
    let hasRunning = sessions.contains { $0.status == .running }
    if hasWaiting || hasAttention {
        return IconState(lamp: .red, blink: hasAttention, breathe: false)
    }
    if hasRunning {
        return IconState(lamp: .orange, blink: false, breathe: true)
    }
    return IconState(lamp: .green, blink: false, breathe: false)
}

/// Alpha for the lit lamp at `phase` seconds. Pure so it is unit-testable;
/// the app advances `phase` via a timer.
public func litAlpha(for state: IconState, phase: Double) -> Double {
    if state.blink {
        let t = phase.truncatingRemainder(dividingBy: 0.6)
        return t < 0.3 ? 1.0 : 0.2
    }
    if state.breathe {
        let cycle = phase.truncatingRemainder(dividingBy: 1.5) / 1.5     // 0..1
        let c = cos(2 * Double.pi * cycle)                                // 1 → -1
        return 0.55 + 0.45 * (0.5 + 0.5 * c)                              // 1.0 … 0.55
    }
    return 1.0
}
