import SwiftUI

/// Настройки отрисовки тепловой карты. Живут во вьюхе карты поля, чтобы
/// пользователь мог подстроить плотность под конкретный вид спорта.
struct HeatMapSettings: Equatable {
    /// Радиус влияния одной метки в точках экрана.
    var radius: CGFloat = 55
    /// Степень контраста: <1 — подсвечивает редкие зоны, >1 — только самые плотные.
    var intensity: Double = 1.0
    /// Общая непрозрачность слоя.
    var opacity: Double = 0.85
    /// Показывать ли кружки меток поверх тепла.
    var showsMarkers: Bool = false

    static let radiusRange: ClosedRange<Double> = 15...140
    static let intensityRange: ClosedRange<Double> = 0.4...2.5
}

/// Тепловая карта позиций меток.
///
/// Важно: координаты считаются ровно той же формулой, что и кружки меток
/// (`normalized * viewSize`), иначе тепло уезжает относительно точек.
/// Плотность копится в сетке экранного пространства и выводится одним
/// CGImage — это на порядки дешевле, чем тысячи градиентных заливок.
struct HeatMapView: View {
    /// Точки в координатах поля (px). Один штамп может дать несколько точек — по одной на карту,
    /// поэтому вход — уже развёрнутый список позиций именно для этой карты.
    let points: [CGPoint]
    let fieldDimensions: (width: CGFloat, height: CGFloat)
    let viewSize: CGSize
    var settings: HeatMapSettings = HeatMapSettings()

    /// Размер ячейки сетки плотности в точках. Меньше — плавнее и дороже.
    private let cellSize: CGFloat = 3

    var body: some View {
        ZStack {
            if let image = renderedImage {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .frame(width: viewSize.width, height: viewSize.height)
                    .opacity(settings.opacity)
            }
        }
        .frame(width: viewSize.width, height: viewSize.height)
        .allowsHitTesting(false)
    }

    private var renderedImage: CGImage? {
        guard viewSize.width > 1, viewSize.height > 1,
              fieldDimensions.width > 0, fieldDimensions.height > 0 else { return nil }

        let gridWidth = max(2, Int((viewSize.width / cellSize).rounded()))
        let gridHeight = max(2, Int((viewSize.height / cellSize).rounded()))

        let density = accumulateDensity(gridWidth: gridWidth, gridHeight: gridHeight)
        guard let maxValue = density.max(), maxValue > 0 else { return nil }

        return makeImage(from: density, width: gridWidth, height: gridHeight, maxValue: maxValue)
    }

    /// Копит гауссову плотность каждой метки в сетке экранного пространства.
    private func accumulateDensity(gridWidth: Int, gridHeight: Int) -> [Float] {
        var grid = [Float](repeating: 0, count: gridWidth * gridHeight)

        let scaleX = CGFloat(gridWidth) / viewSize.width
        let scaleY = CGFloat(gridHeight) / viewSize.height
        // Радиус в ячейках. Ячейки квадратные в экранных точках, поэтому берём средний масштаб.
        let radiusInCells = max(1.0, Double(settings.radius * (scaleX + scaleY) / 2))
        let sigma = radiusInCells / 2.0
        let twoSigmaSquared = Float(2 * sigma * sigma)
        let window = Int(radiusInCells.rounded(.up))

        for position in points {
            guard position.x.isFinite, position.y.isFinite else { continue }

            let normalizedX = position.x / fieldDimensions.width
            let normalizedY = position.y / fieldDimensions.height
            guard normalizedX.isFinite, normalizedY.isFinite,
                  (0...1).contains(normalizedX), (0...1).contains(normalizedY) else { continue }

            let centerX = Double(normalizedX) * Double(gridWidth)
            let centerY = Double(normalizedY) * Double(gridHeight)

            let minX = max(0, Int(centerX) - window)
            let maxX = min(gridWidth - 1, Int(centerX) + window)
            let minY = max(0, Int(centerY) - window)
            let maxY = min(gridHeight - 1, Int(centerY) + window)
            guard minX <= maxX, minY <= maxY else { continue }

            for y in minY...maxY {
                let dy = Double(y) + 0.5 - centerY
                let rowOffset = y * gridWidth
                for x in minX...maxX {
                    let dx = Double(x) + 0.5 - centerX
                    let distanceSquared = Float(dx * dx + dy * dy)
                    guard distanceSquared <= Float(radiusInCells * radiusInCells) else { continue }
                    grid[rowOffset + x] += exp(-distanceSquared / twoSigmaSquared)
                }
            }
        }

        return grid
    }

    private func makeImage(from grid: [Float], width: Int, height: Int, maxValue: Float) -> CGImage? {
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let exponent = 1.0 / max(0.1, settings.intensity)

        for index in 0..<(width * height) {
            let normalized = Double(grid[index] / maxValue)
            guard normalized > 0.001 else { continue }

            let value = pow(min(1.0, max(0.0, normalized)), exponent)
            let color = Self.paletteColor(for: value)
            // Прозрачность плавно нарастает у краёв пятна, чтобы карта поля читалась.
            let alpha = min(1.0, value / 0.22)

            let offset = index * 4
            pixels[offset] = UInt8((color.0 * alpha * 255).rounded())
            pixels[offset + 1] = UInt8((color.1 * alpha * 255).rounded())
            pixels[offset + 2] = UInt8((color.2 * alpha * 255).rounded())
            pixels[offset + 3] = UInt8((alpha * 255).rounded())
        }

        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        return context.makeImage()
    }

    /// Классическая шкала плотности: синий → бирюзовый → зелёный → жёлтый → красный.
    static func paletteColor(for value: Double) -> (Double, Double, Double) {
        let stops: [(position: Double, red: Double, green: Double, blue: Double)] = [
            (0.00, 0.13, 0.28, 0.85),
            (0.25, 0.00, 0.60, 0.95),
            (0.45, 0.00, 0.82, 0.60),
            (0.62, 0.55, 0.90, 0.15),
            (0.78, 0.98, 0.82, 0.05),
            (0.90, 0.99, 0.52, 0.02),
            (1.00, 0.90, 0.10, 0.08)
        ]

        let clamped = min(1.0, max(0.0, value))
        for index in 1..<stops.count {
            let upper = stops[index]
            guard clamped <= upper.position else { continue }
            let lower = stops[index - 1]
            let span = upper.position - lower.position
            let t = span > 0 ? (clamped - lower.position) / span : 0
            return (
                lower.red + (upper.red - lower.red) * t,
                lower.green + (upper.green - lower.green) * t,
                lower.blue + (upper.blue - lower.blue) * t
            )
        }

        let last = stops[stops.count - 1]
        return (last.red, last.green, last.blue)
    }

    static func paletteSwiftUIColor(for value: Double) -> Color {
        let color = paletteColor(for: value)
        return Color(red: color.0, green: color.1, blue: color.2)
    }
}

/// Горизонтальная шкала плотности под тепловой картой.
struct HeatMapLegendView: View {
    var body: some View {
        HStack(spacing: 8) {
            Text(^String.Titles.heatMapLegendLow)
                .font(.system(size: 10))
                .foregroundColor(.secondary)

            LinearGradient(
                gradient: Gradient(colors: stride(from: 0.0, through: 1.0, by: 0.05).map {
                    HeatMapView.paletteSwiftUIColor(for: $0)
                }),
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: 140, height: 8)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Color(NSColor.separatorColor), lineWidth: 0.5))

            Text(^String.Titles.heatMapLegendHigh)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
    }
}

/// Панель настроек тепловой карты: радиус, контраст и показ меток.
struct HeatMapControlsView: View {
    @Binding var settings: HeatMapSettings

    var body: some View {
        HStack(spacing: 16) {
            HeatMapLegendView()

            sliderControl(
                title: ^String.Titles.heatMapControlRadius,
                value: Binding(
                    get: { Double(settings.radius) },
                    set: { settings.radius = CGFloat($0) }
                ),
                range: HeatMapSettings.radiusRange
            )

            sliderControl(
                title: ^String.Titles.heatMapControlIntensity,
                value: $settings.intensity,
                range: HeatMapSettings.intensityRange
            )

            Toggle(^String.Titles.heatMapControlShowMarkers, isOn: $settings.showsMarkers)
                .toggleStyle(CheckboxToggleStyle())
                .font(.system(size: 11))

            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 4)
    }

    private func sliderControl(title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            Slider(value: value, in: range)
                .frame(width: 90)
        }
    }
}
