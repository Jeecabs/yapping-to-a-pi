import Foundation
import CoreGraphics

public enum AppTheme: String, Codable, CaseIterable, Sendable {
    case system, light, dark
    public var title: String { rawValue.capitalized }
}

public enum BarEdge: String, Codable, CaseIterable, Sendable {
    case screen, dock
    public var title: String { self == .screen ? "Bottom of screen" : "Above Dock" }
}

public struct BarPosition: Codable, Equatable, Sendable {
    public var displayID: UInt32
    public var x: Double
    public var y: Double
    public init(displayID: UInt32, x: Double, y: Double) { self.displayID = displayID; self.x = x; self.y = y }
}

/// How far the floating bar opens when the pointer rests on it.
public enum BarHoverDetail: String, Codable, CaseIterable, Sendable {
    case off, compact, full
    public var title: String { rawValue.capitalized }
}

public struct AppearancePreferences: Codable, Equatable, Sendable {
    public var theme: AppTheme = .system
    public var barScale = 1.0
    public var bottomSpacing = 6.0
    public var edge: BarEdge = .screen
    public var opacity = 0.96
    public var position: BarPosition?
    public var meterSensitivity: Double?
    public var hoverDetail: BarHoverDetail?
    public init() {}
    public var scale: Double { barScale.isFinite ? min(1.3, max(0.8, barScale)) : 1 }
    public var sensitivity: Double {
        get { let value = meterSensitivity ?? 1; return value.isFinite ? min(2, max(0.5, value)) : 1 }
        set { meterSensitivity = newValue }
    }
    public var hover: BarHoverDetail {
        get { hoverDetail ?? .full }
        set { hoverDetail = newValue }
    }
}

/// Where the floating bar's panel sits, and which way the bar opens inside it.
public struct OverlayPlacement: Equatable, Sendable {
    public var frame: CGRect
    /// False near the top of the screen, where the bar opens downward instead.
    public var expandsUp: Bool
}

public enum OverlayLayout {
    /// The panel is a fixed canvas around the pill, so the pill can grow and morph inside it without resizing
    /// the window. `row` is the resting pill, `canvas` the panel, and `inset` the gap between pill and panel edge.
    public static func placement(screen: CGRect, visible: CGRect, row: CGSize, canvas: CGSize, inset: Double,
                                 preferences: AppearancePreferences) -> OverlayPlacement {
        let base = preferences.edge == .screen ? screen.minY : visible.minY
        var center = CGPoint(x: screen.midX, y: base + min(120, max(0, preferences.bottomSpacing)) + row.height / 2)
        if let position = preferences.position, position.x.isFinite, position.y.isFinite {
            center = CGPoint(x: screen.minX + screen.width * position.x, y: screen.minY + screen.height * position.y)
        }
        // Keep the whole pill reachable after a display change or a size adjustment.
        center.x = min(max(screen.minX + 2 + row.width / 2, center.x), screen.maxX - 2 - row.width / 2)
        center.y = min(max(screen.minY + 2 + row.height / 2, center.y), visible.maxY - 2 - row.height / 2)
        let expandsUp = center.y - row.height / 2 - inset + canvas.height <= visible.maxY
        let y = expandsUp ? center.y - row.height / 2 - inset : center.y + row.height / 2 + inset - canvas.height
        return OverlayPlacement(frame: CGRect(x: (center.x - canvas.width / 2).rounded(), y: y.rounded(),
                                              width: canvas.width, height: canvas.height), expandsUp: expandsUp)
    }

    /// The pill's centre inside a placed panel, used to remember where it was dragged.
    public static func rowCenter(in frame: CGRect, row: CGSize, inset: Double, expandsUp: Bool) -> CGPoint {
        CGPoint(x: frame.midX, y: expandsUp ? frame.minY + inset + row.height / 2 : frame.maxY - inset - row.height / 2)
    }
}
