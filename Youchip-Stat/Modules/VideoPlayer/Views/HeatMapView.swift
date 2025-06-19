import SwiftUI

struct HeatMapView: View {
    let stamps: [TimelineStamp]
    let fieldDimensions: (width: CGFloat, height: CGFloat)
    let viewSize: CGSize
    
    private let heatPointRadius: CGFloat = 45
    private let heatPointOpacity: Double = 0.4
    private let resolution: (x: Int, y: Int) = (150, 150)
    private let heatIntensity: Float = 0.7
    private let heatRadius: Int = 15
    
    var body: some View {
        Canvas { context, size in
            let scaleX = size.width / fieldDimensions.width
            let scaleY = size.height / fieldDimensions.height
            let scale = min(scaleX, scaleY)
            
            let offsetX = (size.width - fieldDimensions.width * scale) / 2
            let offsetY = (size.height - fieldDimensions.height * scale) / 2
            
            let heatmap = generateHeatmap(size: size, scale: scale, offset: (offsetX, offsetY))
            
            context.drawLayer { ctx in
                let baseGradient = Gradient(colors: [
                    Color.clear,
                    Color.blue.opacity(0.05),
                    Color.blue.opacity(0.1)
                ])
                let baseRect = Path(CGRect(origin: .zero, size: size))
                ctx.fill(baseRect, with: .linearGradient(
                    baseGradient,
                    startPoint: CGPoint(x: 0, y: 0),
                    endPoint: CGPoint(x: size.width, y: size.height)
                ))
                
                for (x, y, intensity) in heatmap {
                    let pointRect = CGRect(
                        x: x - heatPointRadius,
                        y: y - heatPointRadius,
                        width: heatPointRadius * 2,
                        height: heatPointRadius * 2
                    )
                    
                    let colors = heatmapGradientColors(intensity: intensity)
                    let gradient = Gradient(colors: colors)
                    
                    ctx.opacity = heatPointOpacity + (intensity * 0.4)
                    ctx.fill(
                        Path(ellipseIn: pointRect),
                        with: .radialGradient(
                            gradient,
                            center: CGPoint(x: x, y: y),
                            startRadius: 0,
                            endRadius: heatPointRadius
                        )
                    )
                }
            }
            
            context.drawLayer { ctx in
                let hotspots = findHotspots(from: heatmap)
                for (x, y, _) in hotspots {
                    let glowSize = heatPointRadius * 0.7
                    let glowRect = CGRect(
                        x: x - glowSize/2,
                        y: y - glowSize/2,
                        width: glowSize,
                        height: glowSize
                    )
                    
                    ctx.opacity = 0.7
                    ctx.fill(
                        Path(ellipseIn: glowRect),
                        with: .radialGradient(
                            Gradient(colors: [Color.red.opacity(0.8), Color.red.opacity(0.0)]),
                            center: CGPoint(x: x, y: y),
                            startRadius: 0,
                            endRadius: glowSize/2
                        )
                    )
                }
            }
        }
        .frame(width: viewSize.width, height: viewSize.height)
        .blur(radius: 3)
    }
    
    private func findHotspots(from heatmap: [(x: CGFloat, y: CGFloat, intensity: Double)]) -> [(x: CGFloat, y: CGFloat, intensity: Double)] {
        let threshold = 0.85
        return heatmap.filter { $0.intensity > threshold }
    }
    
    private func generateHeatmap(size: CGSize, scale: CGFloat, offset: (x: CGFloat, y: CGFloat)) -> [(x: CGFloat, y: CGFloat, intensity: Double)] {
        var heatPoints: [(x: CGFloat, y: CGFloat, intensity: Double)] = []
        
        if stamps.isEmpty {
            return []
        }
        
        let grid = createHeatmapGrid()
        let smoothedGrid = applyGaussianBlur(to: grid)
        
        for y in 0..<resolution.y {
            for x in 0..<resolution.x {
                let intensity = smoothedGrid[y][x]
                if intensity > 0.05 {
                    let normalizedX = CGFloat(x) / CGFloat(resolution.x)
                    let normalizedY = CGFloat(y) / CGFloat(resolution.y)
                    
                    let fieldX = normalizedX * fieldDimensions.width
                    let fieldY = normalizedY * fieldDimensions.height
                    
                    let pointX = fieldX * scale + offset.x
                    let pointY = fieldY * scale + offset.y + 15
                    
                    heatPoints.append((pointX, pointY, Double(intensity)))
                }
            }
        }
        
        return heatPoints
    }
    
    private func createHeatmapGrid() -> [[Float]] {
        var grid = Array(repeating: Array(repeating: Float(0), count: resolution.x), count: resolution.y)
        
        let stampsWithPosition = stamps.filter { $0.position != nil }
        
        if stampsWithPosition.isEmpty {
            return grid
        }
        
        for stamp in stamps {
            if let position = stamp.position {
                if position.x.isFinite && position.y.isFinite &&
                   position.x >= 0 && position.y >= 0 &&
                   fieldDimensions.width > 0 && fieldDimensions.height > 0 {
                    
                    let normalizedX = position.x / fieldDimensions.width
                    // Инвертируем Y-координату если ось Y направлена сверху вниз
                    let normalizedY = position.y / fieldDimensions.height
                    
                    if normalizedX.isFinite && normalizedY.isFinite &&
                       normalizedX >= 0 && normalizedX <= 1 &&
                       normalizedY >= 0 && normalizedY <= 1 {
                        
                        let gridX = Int(normalizedX * CGFloat(resolution.x))
                        let gridY = Int(normalizedY * CGFloat(resolution.y))
                        
                        if gridX >= 0 && gridX < resolution.x && gridY >= 0 && gridY < resolution.y {
                            addHeat(to: &grid, at: (gridX, gridY))
                        }
                    }
                }
            }
        }
        
        if stampsWithPosition.count < 5 {
            for stamp in stampsWithPosition {
                if let position = stamp.position {
                    let normalizedX = position.x / fieldDimensions.width
                    let normalizedY = position.y / fieldDimensions.height
                    
                    let gridX = Int(normalizedX * CGFloat(resolution.x))
                    let gridY = Int(normalizedY * CGFloat(resolution.y))
                    
                    if gridX >= 0 && gridX < resolution.x && gridY >= 0 && gridY < resolution.y {
                        let extraRadius = heatRadius + 5
                        for dy in -extraRadius...extraRadius {
                            for dx in -extraRadius...extraRadius {
                                let x = gridX + dx
                                let y = gridY + dy
                                
                                if x >= 0 && x < resolution.x && y >= 0 && y < resolution.y {
                                    let distance = sqrt(Float(dx*dx + dy*dy))
                                    
                                    if distance <= Float(extraRadius) {
                                        let factor = pow(1.0 - (distance / Float(extraRadius)), 2)
                                        grid[y][x] += heatIntensity * factor * 0.5
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        
        return grid
    }
    
    private func addHeat(to grid: inout [[Float]], at point: (x: Int, y: Int)) {
        for dy in -heatRadius...heatRadius {
            for dx in -heatRadius...heatRadius {
                let x = point.x + dx
                let y = point.y + dy
                
                if x >= 0 && x < resolution.x && y >= 0 && y < resolution.y {
                    let distance = sqrt(Float(dx*dx + dy*dy))
                    
                    if distance <= Float(heatRadius) {
                        let factor = pow(1.0 - (distance / Float(heatRadius)), 2)
                        grid[y][x] += heatIntensity * factor
                    }
                }
            }
        }
    }
    
    private func applyGaussianBlur(to grid: [[Float]]) -> [[Float]] {
        let kernelSize = 5
        let sigma: Float = 1.4
        
        let kernel = createGaussianKernel(size: kernelSize, sigma: sigma)
        
        var result = Array(repeating: Array(repeating: Float(0), count: resolution.x), count: resolution.y)
        
        for y in 0..<resolution.y {
            for x in 0..<resolution.x {
                var sum: Float = 0
                var weightSum: Float = 0
                
                let halfKernel = kernelSize / 2
                
                for ky in -halfKernel...halfKernel {
                    for kx in -halfKernel...halfKernel {
                        let sampleX = x + kx
                        let sampleY = y + ky
                        
                        if sampleX >= 0 && sampleX < resolution.x && sampleY >= 0 && sampleY < resolution.y {
                            let kernelValue = kernel[ky+halfKernel][kx+halfKernel]
                            sum += grid[sampleY][sampleX] * kernelValue
                            weightSum += kernelValue
                        }
                    }
                }
                
                if weightSum > 0 {
                    result[y][x] = sum / weightSum
                }
            }
        }
        
        normalizeGrid(&result)
        
        return result
    }
    
    private func createGaussianKernel(size: Int, sigma: Float) -> [[Float]] {
        var kernel = Array(repeating: Array(repeating: Float(0), count: size), count: size)
        let center = size / 2
        
        for y in 0..<size {
            for x in 0..<size {
                let dx = Float(x - center)
                let dy = Float(y - center)
                let distance = dx*dx + dy*dy
                
                kernel[y][x] = exp(-distance / (2 * sigma * sigma))
            }
        }
        
        return kernel
    }
    
    private func normalizeGrid(_ grid: inout [[Float]]) {
        var maxValue: Float = 0.0
        
        for row in grid {
            for value in row {
                maxValue = max(maxValue, value)
            }
        }
        
        if maxValue > 0.0 {
            for y in 0..<grid.count {
                for x in 0..<grid[y].count {
                    grid[y][x] /= maxValue
                }
            }
        }
    }
    
    private func heatmapGradientColors(intensity: Double) -> [Color] {
        let i = min(1.0, max(0.0, intensity))
        
        if i < 0.25 {
            return [
                Color.blue.opacity(0.7),
                Color.blue.opacity(0.4),
                Color.blue.opacity(0.1),
                Color.clear
            ]
        } else if i < 0.5 {
            return [
                Color.init(red: 0, green: 0.5, blue: 1.0).opacity(0.8),
                Color.init(red: 0, green: 0.7, blue: 0.7).opacity(0.5),
                Color.init(red: 0, green: 0.7, blue: 0.5).opacity(0.2),
                Color.clear
            ]
        } else if i < 0.75 {
            return [
                Color.init(red: 0.5, green: 1.0, blue: 0).opacity(0.9),
                Color.init(red: 0.7, green: 0.9, blue: 0).opacity(0.6),
                Color.init(red: 0.9, green: 0.9, blue: 0).opacity(0.3),
                Color.clear
            ]
        } else {
            return [
                Color.red.opacity(1.0),
                Color.init(red: 1.0, green: 0.5, blue: 0).opacity(0.7),
                Color.init(red: 1.0, green: 0.7, blue: 0).opacity(0.4),
                Color.clear
            ]
        }
    }
    
    private func heatmapColor(intensity: Double) -> Color {
        let i = min(1.0, max(0.0, intensity))
        
        if i < 0.3 {
            let t = i / 0.3
            return Color(red: 0, green: Double(t) * 0.8, blue: 1.0)
        } else if i < 0.6 {
            let t = (i - 0.3) / 0.3
            return Color(red: Double(t) * 0.9, green: 0.8 + Double(t) * 0.2, blue: 1.0 - Double(t))
        } else if i < 0.8 {
            let t = (i - 0.6) / 0.2
            return Color(red: 0.9 + Double(t) * 0.1, green: 1.0 - Double(t) * 0.3, blue: 0)
        } else {
            let t = (i - 0.8) / 0.2
            return Color(red: 1.0, green: 0.7 - Double(t) * 0.7, blue: 0)
        }
    }
}
