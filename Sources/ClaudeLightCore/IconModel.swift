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
