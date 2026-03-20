//
//  TelestrationModeModels.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 3/20/26.
//

import SwiftUI
import AVFoundation

// MARK: - Telestration Mode Tool

enum TelestrationModeTool: String, CaseIterable, Equatable {
    case playerMarker
    case zone
    case animatedArrow
    
    var displayName: String {
        switch self {
        case .playerMarker: return "Player Marker"
        case .zone: return "Zone"
        case .animatedArrow: return "Animated Arrow"
        }
    }
    
    var iconName: String {
        switch self {
        case .playerMarker: return "person.circle"
        case .zone: return "pentagon"
        case .animatedArrow: return "arrow.right"
        }
    }
}

// MARK: - Pixel Template

struct PixelTemplate {
    let rgbData: [UInt8]
    let width: Int
    let height: Int
}

// MARK: - Tracked Position

struct TrackedPosition: Equatable {
    var center: CGPoint
    var isManualOverride: Bool = false
    
    static func == (lhs: TrackedPosition, rhs: TrackedPosition) -> Bool {
        lhs.center == rhs.center && lhs.isManualOverride == rhs.isManualOverride
    }
}

// MARK: - Player Marker

struct PlayerMarker: Identifiable {
    let id: UUID
    var color: Color
    /// Frame index -> tracked position in image pixel coordinates
    var positions: [Int: TrackedPosition]
    var template: PixelTemplate?
    var radius: CGFloat
    
    init(id: UUID = UUID(), color: Color = .red, radius: CGFloat = 22) {
        self.id = id
        self.color = color
        self.positions = [:]
        self.template = nil
        self.radius = radius
    }
    
    func position(at frameIndex: Int) -> CGPoint? {
        positions[frameIndex]?.center
    }
}

// MARK: - Telestration Zone (Convex Hull)

struct TelestrationZone: Identifiable {
    let id: UUID
    var markerIDs: [UUID]
    var fillColor: Color
    var edgeColor: Color
    var fillOpacity: Double
    
    init(id: UUID = UUID(), markerIDs: [UUID], fillColor: Color = .yellow, edgeColor: Color = .orange, fillOpacity: Double = 0.25) {
        self.id = id
        self.markerIDs = markerIDs
        self.fillColor = fillColor
        self.edgeColor = edgeColor
        self.fillOpacity = fillOpacity
    }
    
    func points(from markers: [PlayerMarker], at frameIndex: Int) -> [CGPoint] {
        markerIDs.compactMap { markerID in
            markers.first(where: { $0.id == markerID })?.position(at: frameIndex)
        }
    }
}

// MARK: - Animated Arrow

struct TelestrationAnimatedArrow: Identifiable {
    let id: UUID
    var startPoint: CGPoint
    var endPoint: CGPoint
    var color: Color
    var lineWidth: CGFloat
    var animationDuration: Double
    
    init(id: UUID = UUID(), startPoint: CGPoint = .zero, endPoint: CGPoint = .zero, color: Color = .white, lineWidth: CGFloat = 3.0, animationDuration: Double = 1.5) {
        self.id = id
        self.startPoint = startPoint
        self.endPoint = endPoint
        self.color = color
        self.lineWidth = lineWidth
        self.animationDuration = animationDuration
    }
}

// MARK: - Arrow Placement Phase

enum ArrowPlacementPhase {
    case placingStart
    case placingEnd
}

// MARK: - Convex Hull

enum ConvexHull {
    static func compute(from points: [CGPoint]) -> [CGPoint] {
        guard points.count >= 3 else { return points }
        
        let sorted = points.sorted { $0.x == $1.x ? $0.y < $1.y : $0.x < $1.x }
        
        var lower: [CGPoint] = []
        for p in sorted {
            while lower.count >= 2 && cross(o: lower[lower.count - 2], a: lower[lower.count - 1], b: p) <= 0 {
                lower.removeLast()
            }
            lower.append(p)
        }
        
        var upper: [CGPoint] = []
        for p in sorted.reversed() {
            while upper.count >= 2 && cross(o: upper[upper.count - 2], a: upper[upper.count - 1], b: p) <= 0 {
                upper.removeLast()
            }
            upper.append(p)
        }
        
        lower.removeLast()
        upper.removeLast()
        return lower + upper
    }
    
    private static func cross(o: CGPoint, a: CGPoint, b: CGPoint) -> CGFloat {
        (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x)
    }
}
