import Foundation

/// Only interprets the chosen key. The platform adapter owns event taps and key codes.
public struct ShortcutGesture: Sendable {
    public enum Action: Equatable, Sendable { case start, stop, cancel }
    private var pressedAt: TimeInterval?
    private var lastTap: TimeInterval?
    private var suppressHold = false
    public private(set) var handsFree = false
    public private(set) var active = false
    public init() {}

    public mutating func press(at time: TimeInterval) -> Action? {
        guard pressedAt == nil else { return nil }
        pressedAt = time
        suppressHold = false
        if handsFree { handsFree = false; active = false; lastTap = nil; suppressHold = true; return .stop }
        if let lastTap, time - lastTap < 0.35 {
            handsFree = true; active = true; self.lastTap = nil; return .start
        }
        return nil
    }

    public mutating func hold() -> Action? {
        guard pressedAt != nil, !active, !handsFree, !suppressHold else { return nil }
        active = true
        return .start
    }

    public mutating func release(at time: TimeInterval) -> Action? {
        guard let pressedAt else { return nil }
        self.pressedAt = nil
        if suppressHold { suppressHold = false; return nil }
        if handsFree { return nil }
        if active { active = false; lastTap = nil; return .stop }
        if time - pressedAt < 0.22 { lastTap = time }
        return nil
    }

    public mutating func toggle() -> Action {
        lastTap = nil
        if handsFree { handsFree = false; active = false; return .stop }
        handsFree = true
        active = true
        // An active hold changes to hands-free without starting a second recording.
        return .start
    }

    public mutating func reset() {
        pressedAt = nil; lastTap = nil; handsFree = false; active = false; suppressHold = false
    }
}
