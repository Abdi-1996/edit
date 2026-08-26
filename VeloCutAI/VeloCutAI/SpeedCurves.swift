import SwiftUI
import Foundation

enum CurveInterpolation: String, CaseIterable, Identifiable, Codable {
    case smooth = "Smooth"
    case linear = "Linear"
    case sharp = "Sharp"
    var id: String { rawValue }
}

enum SpeedFXMode: String, CaseIterable, Identifiable, Codable {
    case multiply = "Multiply"
    case override = "Override"
    var id: String { rawValue }
}

struct SpeedPoint: Identifiable, Equatable, Codable {
    var id: UUID = UUID()
    var t: Double
    var speed: Double
}

struct SpeedCurve: Equatable, Codable {
    var points: [SpeedPoint]
    var interpolation: CurveInterpolation = .smooth

    static let flat = SpeedCurve(points: [
        SpeedPoint(t: 0, speed: 1),
        SpeedPoint(t: 1, speed: 1)
    ])

    func value(at rawT: Double) -> Double {
        let t = min(max(rawT, 0), 1)
        let sorted = points.sorted { $0.t < $1.t }
        guard let first = sorted.first, let last = sorted.last else { return 1 }
        if t <= first.t { return clampSpeed(first.speed) }
        if t >= last.t { return clampSpeed(last.speed) }
        guard let rightIndex = sorted.firstIndex(where: { $0.t >= t }), rightIndex > 0 else { return 1 }
        let a = sorted[rightIndex - 1]
        let b = sorted[rightIndex]
        let span = max(0.0001, b.t - a.t)
        var u = (t - a.t) / span
        switch interpolation {
        case .linear: break
        case .smooth:
            u = u * u * (3 - 2 * u)
        case .sharp:
            if u < 0.5 { u = 0.5 * pow(u * 2, 2.6) }
            else { u = 1 - 0.5 * pow((1 - u) * 2, 2.6) }
        }
        return clampSpeed(a.speed + (b.speed - a.speed) * u)
    }

    mutating func normalize() {
        points = points.map { SpeedPoint(id: $0.id, t: min(max($0.t, 0), 1), speed: clampSpeed($0.speed)) }
            .sorted { $0.t < $1.t }
        if points.isEmpty { points = SpeedCurve.flat.points }
        if let first = points.first, first.t > 0.001 { points.insert(SpeedPoint(t: 0, speed: first.speed), at: 0) }
        if let last = points.last, last.t < 0.999 { points.append(SpeedPoint(t: 1, speed: last.speed)) }
    }

    mutating func mirror() {
        points = points.map { SpeedPoint(id: $0.id, t: 1 - $0.t, speed: $0.speed) }.sorted { $0.t < $1.t }
    }

    mutating func movePoint(id: UUID, t: Double, speed: Double) {
        guard let index = points.firstIndex(where: { $0.id == id }) else { return }
        var newT = min(max(t, 0), 1)
        if index == 0 { newT = 0 }
        if index == points.count - 1 { newT = 1 }
        points[index].t = newT
        points[index].speed = clampSpeed(speed)
        points.sort { $0.t < $1.t }
    }

    mutating func addPoint(t: Double, speed: Double? = nil) {
        let safeT = min(max(t, 0.01), 0.99)
        points.append(SpeedPoint(t: safeT, speed: speed ?? value(at: safeT)))
        points.sort { $0.t < $1.t }
    }

    mutating func deletePoint(_ id: UUID) {
        guard points.count > 2, let index = points.firstIndex(where: { $0.id == id }), index != 0, index != points.count - 1 else { return }
        points.remove(at: index)
    }
}

func clampSpeed(_ value: Double) -> Double { min(max(value, 0.05), 20) }

struct SpeedCurvePreset: Identifiable, Equatable {
    let id: String
    let name: String
    let category: String
    let curve: SpeedCurve

    static let all: [SpeedCurvePreset] = [
        .init(id: "velocity", name: "Velocity", category: "Trending", curve: curve([(0,1),(0.22,1),(0.38,0.25),(0.52,5.2),(0.70,0.45),(1,1)])),
        .init(id: "tiktok", name: "TikTok Ramp", category: "Trending", curve: curve([(0,1),(0.18,1),(0.34,0.4),(0.49,8),(0.63,0.35),(0.82,1),(1,1)])),
        .init(id: "flash", name: "Flash Ramp", category: "Impact", curve: curve([(0,1),(0.36,1),(0.48,10),(0.57,0.2),(0.74,1),(1,1)])),
        .init(id: "anime", name: "Anime Impact", category: "Anime/AMV", curve: curve([(0,1),(0.28,1),(0.42,0.15),(0.54,6.5),(0.67,0.3),(0.84,1),(1,1)])),
        .init(id: "amv", name: "AMV Smooth", category: "Anime/AMV", curve: curve([(0,1),(0.22,0.55),(0.50,3.2),(0.78,0.55),(1,1)])),
        .init(id: "whip", name: "Whip", category: "Transition", curve: curve([(0,1),(0.38,1),(0.50,12),(0.64,1),(1,1)])),
        .init(id: "punch", name: "Punch", category: "Impact", curve: curve([(0,1),(0.40,0.2),(0.52,7),(0.68,1),(1,1)])),
        .init(id: "zoomhit", name: "Zoom Hit", category: "Impact", curve: curve([(0,1),(0.28,0.35),(0.48,5),(0.66,0.35),(0.82,1),(1,1)])),
        .init(id: "beatdrop", name: "Beat Drop", category: "Trending", curve: curve([(0,1),(0.25,0.7),(0.44,0.2),(0.53,8),(0.66,1.6),(0.82,1),(1,1)])),
        .init(id: "velocitypro", name: "Velocity Pro", category: "Trending", curve: curve([(0,1),(0.16,0.55),(0.29,4.5),(0.40,0.22),(0.52,8.5),(0.65,0.32),(0.79,3.4),(1,1)])),
        .init(id: "micro", name: "Micro Hit", category: "Impact", curve: curve([(0,1),(0.44,1),(0.49,5.5),(0.56,0.45),(0.66,1),(1,1)])),
        .init(id: "smoothpush", name: "Smooth Push", category: "Smooth", curve: curve([(0,1),(0.22,0.75),(0.50,2.4),(0.78,0.75),(1,1)]))
    ]

    static func named(_ id: String) -> SpeedCurvePreset { all.first(where: { $0.id == id }) ?? all[1] }

    private static func curve(_ values: [(Double, Double)]) -> SpeedCurve {
        SpeedCurve(points: values.map { SpeedPoint(t: $0.0, speed: $0.1) }, interpolation: .smooth)
    }
}

struct GlobalSpeedFX: Identifiable, Equatable, Codable {
    var id: UUID = UUID()
    var name: String
    var start: Double
    var duration: Double
    var curve: SpeedCurve
    var strength: Double = 1
    var mode: SpeedFXMode = .multiply
    var isEnabled: Bool = true

    var end: Double { start + max(0.08, duration) }

    func factor(at projectTime: Double) -> Double? {
        guard isEnabled, projectTime >= start, projectTime <= end else { return nil }
        let n = (projectTime - start) / max(0.08, duration)
        let raw = curve.value(at: n)
        return clampSpeed(1 + (raw - 1) * strength)
    }
}

enum CurveTarget: Identifiable, Equatable {
    case clip(UUID)
    case global(UUID)
    var id: String {
        switch self {
        case .clip(let id): return "clip-\(id.uuidString)"
        case .global(let id): return "global-\(id.uuidString)"
        }
    }
}

struct CurveThumbnail: View {
    let curve: SpeedCurve
    var lineWidth: CGFloat = 2
    var body: some View {
        Canvas { context, size in
            guard size.width > 1, size.height > 1 else { return }
            var path = Path()
            for i in 0...50 {
                let t = Double(i) / 50
                let x = CGFloat(t) * size.width
                let y = speedY(curve.value(at: t), height: size.height)
                if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                else { path.addLine(to: CGPoint(x: x, y: y)) }
            }
            context.stroke(path, with: .color(.accentColor), lineWidth: lineWidth)
        }
    }
}

struct InteractiveCurveView: View {
    let curve: SpeedCurve
    let selectedPointID: UUID?
    let onSelect: (UUID) -> Void
    let onMove: (UUID, Double, Double) -> Void
    let onAdd: (Double, Double) -> Void

    var body: some View {
        GeometryReader { geo in
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.secondary.opacity(0.08))
                Canvas { context, size in
                    for speed in [0.1, 0.25, 0.5, 1, 2, 5, 10, 20] as [Double] {
                        let y = speedY(speed, height: size.height)
                        var p = Path(); p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: size.width, y: y))
                        context.stroke(p, with: .color(speed == 1 ? .secondary.opacity(0.45) : .secondary.opacity(0.16)), lineWidth: speed == 1 ? 1.2 : 0.6)
                        let label = context.resolve(Text("\(speed, specifier: "%g")×").font(.system(size: 8, design: .monospaced)).foregroundStyle(.secondary))
                        context.draw(label, at: CGPoint(x: 5, y: y - 2), anchor: .bottomLeading)
                    }
                    var curvePath = Path()
                    for i in 0...160 {
                        let t = Double(i) / 160
                        let x = CGFloat(t) * size.width
                        let y = speedY(curve.value(at: t), height: size.height)
                        if i == 0 { curvePath.move(to: CGPoint(x: x, y: y)) } else { curvePath.addLine(to: CGPoint(x: x, y: y)) }
                    }
                    context.stroke(curvePath, with: .color(.accentColor), lineWidth: 3)
                }
                ForEach(curve.points) { point in
                    Circle()
                        .fill(point.id == selectedPointID ? Color.white : Color.accentColor)
                        .overlay(Circle().stroke(Color.accentColor, lineWidth: 2))
                        .frame(width: point.id == selectedPointID ? 18 : 14, height: point.id == selectedPointID ? 18 : 14)
                        .position(x: CGFloat(point.t) * geo.size.width, y: speedY(point.speed, height: geo.size.height))
                        .contentShape(Rectangle().inset(by: -12))
                        .onTapGesture { onSelect(point.id) }
                        .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                            onSelect(point.id)
                            let t = min(max(Double(value.location.x / max(1, geo.size.width)), 0), 1)
                            let speed = ySpeed(value.location.y, height: geo.size.height)
                            onMove(point.id, t, speed)
                        })
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { location in
                let t = min(max(Double(location.x / max(1, geo.size.width)), 0.01), 0.99)
                onAdd(t, ySpeed(location.y, height: geo.size.height))
            }
        }
    }
}

func speedY(_ speed: Double, height: CGFloat) -> CGFloat {
    let minS = 0.05, maxS = 20.0
    let n = (log(clampSpeed(speed)) - log(minS)) / (log(maxS) - log(minS))
    return height * CGFloat(1 - n)
}

func ySpeed(_ y: CGFloat, height: CGFloat) -> Double {
    let minS = 0.05, maxS = 20.0
    let n = 1 - Double(min(max(y / max(1, height), 0), 1))
    return clampSpeed(exp(log(minS) + n * (log(maxS) - log(minS))))
}
