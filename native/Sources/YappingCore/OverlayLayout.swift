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

public struct AppearancePreferences: Codable, Equatable, Sendable {
    public var theme: AppTheme = .system
    public var barScale = 1.0
    public var bottomSpacing = 6.0
    public var edge: BarEdge = .screen
    public var opacity = 0.96
    public var position: BarPosition?
    public var meterSensitivity: Double?
    public init() {}
    public var scale: Double { barScale.isFinite ? min(1.3, max(0.8, barScale)) : 1 }
    public var sensitivity: Double {
        get { let value = meterSensitivity ?? 1; return value.isFinite ? min(2, max(0.5, value)) : 1 }
        set { meterSensitivity = newValue }
    }
}

public enum OverlayLayout {
    public static func frame(screen: CGRect, visible: CGRect, size: CGSize, preferences: AppearancePreferences) -> CGRect {
        var x = screen.midX - size.width / 2
        var y = (preferences.edge == .screen ? screen.minY : visible.minY) + min(120, max(0, preferences.bottomSpacing))
        if let position = preferences.position, position.x.isFinite, position.y.isFinite {
            x = screen.minX + screen.width * position.x - size.width / 2
            y = screen.minY + screen.height * position.y - size.height / 2
        }
        // Keep the whole pill reachable after a display change or a size adjustment.
        x = min(max(screen.minX + 2, x), screen.maxX - size.width - 2)
        y = min(max(screen.minY + 2, y), visible.maxY - size.height - 2)
        return CGRect(x: x.rounded(), y: y.rounded(), width: size.width, height: size.height)
    }
}
