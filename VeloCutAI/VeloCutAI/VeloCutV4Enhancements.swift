import SwiftUI
import Foundation

// Extra editing interactions layered on top of the original v0.4 editor.
extension EditorViewModel {
    func beginInteractiveEdit() {
        registerUndo()
    }

    func setTrimStartInteractive(_ id: UUID, _ value: Double) {
        guard let i = clips.firstIndex(where: { $0.id == id }) else { return }
        clips[i].trimStart = min(max(0, value), clips[i].trimEnd - 0.05)
        selectedClipID = id
        projectTime = min(projectTime, projectDuration)
        schedulePreview()
    }

    func setTrimEndInteractive(_ id: UUID, _ value: Double) {
        guard let i = clips.firstIndex(where: { $0.id == id }) else { return }
        clips[i].trimEnd = max(min(clips[i].duration, value), clips[i].trimStart + 0.05)
        selectedClipID = id
        projectTime = min(projectTime, projectDuration)
        schedulePreview()
    }

    func setSpeedFXStartInteractive(_ id: UUID, start: Double, duration: Double) {
        guard let i = speedFX.firstIndex(where: { $0.id == id }) else { return }
        let safeDuration = max(0.08, duration)
        speedFX[i].start = max(0, start)
        speedFX[i].duration = safeDuration
        schedulePreview()
    }

    func setSpeedFXDurationInteractive(_ id: UUID, _ duration: Double) {
        guard let i = speedFX.firstIndex(where: { $0.id == id }) else { return }
        speedFX[i].duration = min(max(duration, 0.08), 8)
        schedulePreview()
    }

    func seekCurveTarget(_ target: CurveTarget, normalized: Double) {
        let n = min(max(normalized, 0), 1)
        switch target {
        case .clip(let id):
            guard let layout = layout(for: id) else { return }
            seekProject(to: layout.start + layout.duration * n, exact: true)
        case .global(let id):
            guard let fx = speedFX.first(where: { $0.id == id }) else { return }
            seekProject(to: fx.start + fx.duration * n, exact: true)
        }
    }

    func curveProjectTime(_ target: CurveTarget, normalized: Double) -> Double {
        let n = min(max(normalized, 0), 1)
        switch target {
        case .clip(let id):
            guard let layout = layout(for: id) else { return projectTime }
            return layout.start + layout.duration * n
        case .global(let id):
            guard let fx = speedFX.first(where: { $0.id == id }) else { return projectTime }
            return fx.start + fx.duration * n
        }
    }
}

struct TimelineTrimHandleV4: View {
    let leading: Bool
    let currentValue: Double
    let pps: Double
    let sourcePerOutput: Double
    let onBegin: () -> Void
    let onChange: (Double) -> Void
    @State private var anchor: Double?

    var body: some View {
        Capsule()
            .fill(Color.white.opacity(0.95))
            .overlay(Capsule().stroke(Color.accentColor.opacity(0.65), lineWidth: 1))
            .frame(width: 12, height: 38)
            .contentShape(Rectangle().inset(by: -10))
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if anchor == nil {
                            anchor = currentValue
                            onBegin()
                        }
                        let deltaOutput = Double(value.translation.width) / max(1, pps)
                        let deltaSource = deltaOutput * max(0.02, sourcePerOutput)
                        onChange((anchor ?? currentValue) + deltaSource)
                    }
                    .onEnded { _ in anchor = nil }
            )
    }
}

struct SpeedFXEdgeHandleV4: View {
    let leading: Bool
    let start: Double
    let duration: Double
    let pps: Double
    let onBegin: () -> Void
    let onChange: (Double, Double) -> Void
    @State private var anchorStart: Double?
    @State private var anchorDuration: Double?

    var body: some View {
        Capsule()
            .fill(Color.white.opacity(0.9))
            .frame(width: 9, height: 26)
            .contentShape(Rectangle().inset(by: -10))
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if anchorStart == nil {
                            anchorStart = start
                            anchorDuration = duration
                            onBegin()
                        }
                        let baseStart = anchorStart ?? start
                        let baseDuration = anchorDuration ?? duration
                        let delta = Double(value.translation.width) / max(1, pps)
                        if leading {
                            let maxDelta = baseDuration - 0.08
                            let safeDelta = min(delta, maxDelta)
                            let newStart = max(0, baseStart + safeDelta)
                            let actualDelta = newStart - baseStart
                            onChange(newStart, max(0.08, baseDuration - actualDelta))
                        } else {
                            onChange(baseStart, min(max(baseDuration + delta, 0.08), 8))
                        }
                    }
                    .onEnded { _ in
                        anchorStart = nil
                        anchorDuration = nil
                    }
            )
    }
}

struct InlineCurveEditorV4: View {
    @ObservedObject var model: EditorViewModel
    let target: CurveTarget
    let onOpen: () -> Void
    @State private var selectedPointID: UUID?

    var body: some View {
        GeometryReader { geo in
            let curve = model.curve(for: target)
            ZStack {
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color.accentColor.opacity(0.055))

                Canvas { context, size in
                    var path = Path()
                    for i in 0...90 {
                        let t = Double(i) / 90
                        let point = CGPoint(x: CGFloat(t) * size.width, y: speedY(curve.value(at: t), height: size.height))
                        if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
                    }
                    context.stroke(path, with: .color(.accentColor), lineWidth: 2)
                }

                Rectangle()
                    .fill(Color.red.opacity(0.9))
                    .frame(width: 1.5)
                    .position(x: CGFloat(model.normalizedPlayhead(for: target)) * geo.size.width, y: geo.size.height / 2)
                    .allowsHitTesting(false)

                ForEach(curve.points) { point in
                    Circle()
                        .fill(point.id == selectedPointID ? Color.white : Color.accentColor)
                        .overlay(Circle().stroke(Color.accentColor, lineWidth: 1.5))
                        .frame(width: point.id == selectedPointID ? 13 : 10, height: point.id == selectedPointID ? 13 : 10)
                        .position(x: CGFloat(point.t) * geo.size.width, y: speedY(point.speed, height: geo.size.height))
                        .contentShape(Rectangle().inset(by: -10))
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    selectedPointID = point.id
                                    let t = min(max(Double(value.location.x / max(1, geo.size.width)), 0), 1)
                                    let speed = ySpeed(value.location.y, height: geo.size.height)
                                    model.moveCurvePoint(target, pointID: point.id, t: t, speed: speed)
                                    model.seekCurveTarget(target, normalized: t)
                                }
                        )
                        .onTapGesture { selectedPointID = point.id }
                }

                VStack {
                    HStack {
                        Spacer()
                        Button(action: onOpen) {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .font(.system(size: 9, weight: .bold))
                                .frame(width: 24, height: 24)
                                .background(.thinMaterial, in: Circle())
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                }
                .padding(3)
            }
            .contentShape(Rectangle())
            .onTapGesture { location in
                let t = min(max(Double(location.x / max(1, geo.size.width)), 0.01), 0.99)
                model.addCurvePoint(target, t: t, speed: curve.value(at: t))
                model.seekCurveTarget(target, normalized: t)
            }
        }
    }
}

struct CurveEditorGraphV4: View {
    @ObservedObject var model: EditorViewModel
    let target: CurveTarget
    @Binding var selectedPointID: UUID?

    var body: some View {
        GeometryReader { geo in
            ZStack {
                InteractiveCurveView(
                    curve: model.curve(for: target),
                    selectedPointID: selectedPointID,
                    onSelect: { selectedPointID = $0 },
                    onMove: { id, t, speed in
                        model.moveCurvePoint(target, pointID: id, t: t, speed: speed)
                        model.seekCurveTarget(target, normalized: t)
                    },
                    onAdd: { t, speed in
                        model.addCurvePoint(target, t: t, speed: speed)
                        model.seekCurveTarget(target, normalized: t)
                    }
                )

                Rectangle()
                    .fill(Color.red.opacity(0.9))
                    .frame(width: 2)
                    .position(x: CGFloat(model.normalizedPlayhead(for: target)) * geo.size.width, y: geo.size.height / 2)
                    .allowsHitTesting(false)
            }
        }
    }
}
