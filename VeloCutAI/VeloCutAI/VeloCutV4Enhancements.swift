import SwiftUI
import AVKit
import Foundation

// Extra editing interactions layered on top of the original v0.4 editor.
extension EditorViewModel {
    func beginInteractiveEdit() {
        player.pause()
        isPlaying = false
        registerUndo()
    }

    func finishInteractiveEdit() {
        projectTime = min(max(0, projectTime), projectDuration)
        schedulePreview(immediate: true)
    }

    func setTrimStartInteractive(_ id: UUID, _ value: Double) {
        guard let i = clips.firstIndex(where: { $0.id == id }) else { return }
        objectWillChange.send()
        clips[i].trimStart = min(max(0, value), clips[i].trimEnd - 0.05)
        selectedClipID = id
        // Do not rebuild AVFoundation composition while the finger is moving.
    }

    func setTrimEndInteractive(_ id: UUID, _ value: Double) {
        guard let i = clips.firstIndex(where: { $0.id == id }) else { return }
        objectWillChange.send()
        clips[i].trimEnd = max(min(clips[i].duration, value), clips[i].trimStart + 0.05)
        selectedClipID = id
    }

    func setSpeedFXStartInteractive(_ id: UUID, start: Double, duration: Double) {
        guard let i = speedFX.firstIndex(where: { $0.id == id }) else { return }
        objectWillChange.send()
        let safeDuration = max(0.08, duration)
        speedFX[i].start = max(0, start)
        speedFX[i].duration = safeDuration
    }

    func setSpeedFXDurationInteractive(_ id: UUID, _ duration: Double) {
        guard let i = speedFX.firstIndex(where: { $0.id == id }) else { return }
        objectWillChange.send()
        speedFX[i].duration = min(max(duration, 0.08), 8)
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

    func setCurvePlayheadVisual(_ target: CurveTarget, normalized: Double) {
        let n = min(max(normalized, 0), 1)
        switch target {
        case .clip(let id):
            guard let layout = layout(for: id) else { return }
            projectTime = min(max(0, layout.start + layout.duration * n), projectDuration)
        case .global(let id):
            guard let fx = speedFX.first(where: { $0.id == id }) else { return }
            projectTime = min(max(0, fx.start + fx.duration * n), projectDuration)
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

    func beginCurvePointEdit() {
        player.pause()
        isPlaying = false
        registerUndo()
    }

    func moveCurvePointInteractive(_ target: CurveTarget, pointID: UUID, t: Double, speed: Double) {
        objectWillChange.send()
        switch target {
        case .clip(let id):
            guard let i = clips.firstIndex(where: { $0.id == id }) else { return }
            clips[i].speedCurve.movePoint(id: pointID, t: t, speed: speed)
            clips[i].curveEnabled = true
        case .global(let id):
            guard let i = speedFX.firstIndex(where: { $0.id == id }) else { return }
            speedFX[i].curve.movePoint(id: pointID, t: t, speed: speed)
        }
        // Intentionally no schedulePreview() here. It made the drag restart/jump.
    }

    func finishCurvePointEdit(_ target: CurveTarget, normalized: Double) {
        let n = min(max(normalized, 0), 1)
        setCurvePlayheadVisual(target, normalized: n)
        schedulePreview(immediate: true)
    }
}

struct FullscreenPreviewV4: View {
    let player: AVPlayer
    let onClose: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            PlayerView(player: player)
                .ignoresSafeArea()

            VStack {
                HStack {
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 42, height: 42)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                }
                Spacer()
                Button {
                    if player.rate == 0 { player.play() } else { player.pause() }
                } label: {
                    Image(systemName: player.rate == 0 ? "play.fill" : "pause.fill")
                        .font(.title2)
                        .foregroundStyle(.white)
                        .frame(width: 58, height: 58)
                        .background(.ultraThinMaterial, in: Circle())
                }
            }
            .padding(18)
        }
        .statusBarHidden(true)
    }
}

struct LaneHeightHandleV4: View {
    let height: CGFloat
    let onChange: (CGFloat) -> Void
    @State private var anchorHeight: CGFloat?
    @State private var anchorY: CGFloat?

    var body: some View {
        ZStack {
            Rectangle().fill(Color.clear)
            Capsule()
                .fill(Color.secondary.opacity(0.6))
                .frame(width: 32, height: 5)
        }
        .frame(width: 50, height: 30)
        .contentShape(Rectangle())
        .highPriorityGesture(
            DragGesture(minimumDistance: 1, coordinateSpace: .global)
                .onChanged { value in
                    if anchorHeight == nil {
                        anchorHeight = height
                        anchorY = value.startLocation.y
                    }
                    let delta = value.location.y - (anchorY ?? value.startLocation.y)
                    let newHeight = min(max((anchorHeight ?? height) + delta, 38), 150)
                    onChange(newHeight)
                }
                .onEnded { _ in
                    anchorHeight = nil
                    anchorY = nil
                }
        )
    }
}

struct TimelineTrimHandleV4: View {
    let leading: Bool
    let currentValue: Double
    let pps: Double
    let sourcePerOutput: Double
    var height: CGFloat = 38
    let onBegin: () -> Void
    let onChange: (Double) -> Void
    var onEnd: () -> Void = {}
    @State private var anchorValue: Double?
    @State private var anchorX: CGFloat?

    var body: some View {
        ZStack {
            Rectangle().fill(Color.clear)
            Capsule()
                .fill(Color.white.opacity(0.96))
                .overlay(Capsule().stroke(Color.accentColor.opacity(0.7), lineWidth: 1))
                .frame(width: 12, height: max(28, height))
        }
        .frame(width: 34, height: max(40, height + 8))
        .contentShape(Rectangle())
        .highPriorityGesture(
            DragGesture(minimumDistance: 1, coordinateSpace: .global)
                .onChanged { value in
                    if anchorValue == nil {
                        anchorValue = currentValue
                        anchorX = value.startLocation.x
                        onBegin()
                    }
                    let dx = value.location.x - (anchorX ?? value.startLocation.x)
                    let deltaOutput = Double(dx) / max(1, pps)
                    let deltaSource = deltaOutput * max(0.02, sourcePerOutput)
                    onChange((anchorValue ?? currentValue) + deltaSource)
                }
                .onEnded { _ in
                    anchorValue = nil
                    anchorX = nil
                    onEnd()
                }
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
    var onEnd: () -> Void = {}
    @State private var anchorStart: Double?
    @State private var anchorDuration: Double?
    @State private var anchorX: CGFloat?

    var body: some View {
        ZStack {
            Rectangle().fill(Color.clear)
            Capsule()
                .fill(Color.white.opacity(0.92))
                .frame(width: 9, height: 26)
        }
        .frame(width: 32, height: 38)
        .contentShape(Rectangle())
        .highPriorityGesture(
            DragGesture(minimumDistance: 1, coordinateSpace: .global)
                .onChanged { value in
                    if anchorStart == nil {
                        anchorStart = start
                        anchorDuration = duration
                        anchorX = value.startLocation.x
                        onBegin()
                    }
                    let baseStart = anchorStart ?? start
                    let baseDuration = anchorDuration ?? duration
                    let dx = value.location.x - (anchorX ?? value.startLocation.x)
                    let delta = Double(dx) / max(1, pps)
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
                    anchorX = nil
                    onEnd()
                }
        )
    }
}

struct ResizableTimelineClipCardV4: View {
    let clip: EditorClip
    let index: Int
    let width: Double
    let height: CGFloat
    let selected: Bool
    let onTap: () -> Void
    let onMenu: () -> Void
    let onMove: (CGSize) -> Void
    @State private var drag: CGSize = .zero

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(selected ? Color.accentColor.opacity(0.24) : Color.secondary.opacity(0.14))
            VStack {
                HStack {
                    Text("\(index + 1)").font(.system(size: 8, weight: .bold))
                    Spacer()
                    Text("\(clip.baseSpeed, specifier: "%g")×\(clip.curveEnabled ? " • curve" : "")")
                        .font(.system(size: 8))
                }
                Spacer()
                Text(clip.name).font(.system(size: 8)).lineLimit(1)
            }
            .padding(5)
        }
        .frame(width: width, height: max(40, height))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(selected ? Color.accentColor : .clear, lineWidth: 2))
        .offset(drag)
        .onTapGesture { onTap() }
        .highPriorityGesture(
            LongPressGesture(minimumDuration: 0.32)
                .sequenced(before: DragGesture(minimumDistance: 0))
                .onChanged { value in
                    if case .second(true, let d) = value, let d { drag = d.translation }
                }
                .onEnded { value in
                    defer { drag = .zero }
                    if case .second(true, let d) = value, let d {
                        hypot(d.translation.width, d.translation.height) < 10 ? onMenu() : onMove(d.translation)
                    } else {
                        onMenu()
                    }
                }
        )
    }
}

// Tap a point once to select it. Then drag anywhere inside the graph to move
// the selected point. This avoids SwiftUI losing the gesture when the point
// itself moves underneath the finger.
struct InlineCurveEditorV4: View {
    @ObservedObject var model: EditorViewModel
    let target: CurveTarget
    let onOpen: () -> Void
    @State private var selectedPointID: UUID?
    @State private var editingCurve = false

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
                        let p = CGPoint(x: CGFloat(t) * size.width, y: speedY(curve.value(at: t), height: size.height))
                        if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
                    }
                    context.stroke(path, with: .color(.accentColor), lineWidth: 2)
                }
                .allowsHitTesting(false)

                Rectangle()
                    .fill(Color.red.opacity(0.9))
                    .frame(width: 1.5)
                    .position(x: CGFloat(model.normalizedPlayhead(for: target)) * geo.size.width, y: geo.size.height / 2)
                    .allowsHitTesting(false)

                ForEach(curve.points) { point in
                    Button {
                        selectedPointID = point.id
                    } label: {
                        ZStack {
                            Circle().fill(Color.clear).frame(width: 42, height: 42)
                            Circle()
                                .fill(point.id == selectedPointID ? Color.white : Color.accentColor)
                                .overlay(Circle().stroke(Color.accentColor, lineWidth: 1.5))
                                .frame(width: point.id == selectedPointID ? 17 : 12, height: point.id == selectedPointID ? 17 : 12)
                        }
                    }
                    .buttonStyle(.plain)
                    .position(x: CGFloat(point.t) * geo.size.width, y: speedY(point.speed, height: geo.size.height))
                }

                VStack {
                    HStack {
                        if selectedPointID != nil {
                            Text("Точка выбрана")
                                .font(.system(size: 8, weight: .semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(.thinMaterial, in: Capsule())
                        }
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
            .simultaneousGesture(
                DragGesture(minimumDistance: 5, coordinateSpace: .local)
                    .onChanged { value in
                        guard let id = selectedPointID else { return }
                        if !editingCurve {
                            editingCurve = true
                            model.beginCurvePointEdit()
                        }
                        let t = min(max(Double(value.location.x / max(1, geo.size.width)), 0), 1)
                        let speed = ySpeed(value.location.y, height: geo.size.height)
                        model.moveCurvePointInteractive(target, pointID: id, t: t, speed: speed)
                        model.setCurvePlayheadVisual(target, normalized: t)
                    }
                    .onEnded { value in
                        guard selectedPointID != nil, editingCurve else { return }
                        let t = min(max(Double(value.location.x / max(1, geo.size.width)), 0), 1)
                        editingCurve = false
                        model.finishCurvePointEdit(target, normalized: t)
                    }
            )
            .onTapGesture(count: 2) { location in
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
    @State private var editingCurve = false

    var body: some View {
        GeometryReader { geo in
            let curve = model.curve(for: target)
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.secondary.opacity(0.08))

                Canvas { context, size in
                    for speed in [0.1, 0.25, 0.5, 1, 2, 5, 10, 20] as [Double] {
                        let y = speedY(speed, height: size.height)
                        var grid = Path()
                        grid.move(to: CGPoint(x: 0, y: y))
                        grid.addLine(to: CGPoint(x: size.width, y: y))
                        context.stroke(grid, with: .color(speed == 1 ? .secondary.opacity(0.45) : .secondary.opacity(0.16)), lineWidth: speed == 1 ? 1.2 : 0.6)
                        let label = context.resolve(Text("\(speed, specifier: "%g")×").font(.system(size: 8, design: .monospaced)).foregroundStyle(.secondary))
                        context.draw(label, at: CGPoint(x: 5, y: y - 2), anchor: .bottomLeading)
                    }

                    var path = Path()
                    for i in 0...160 {
                        let t = Double(i) / 160
                        let p = CGPoint(x: CGFloat(t) * size.width, y: speedY(curve.value(at: t), height: size.height))
                        if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
                    }
                    context.stroke(path, with: .color(.accentColor), lineWidth: 3)
                }
                .allowsHitTesting(false)

                Rectangle()
                    .fill(Color.red.opacity(0.9))
                    .frame(width: 2)
                    .position(x: CGFloat(model.normalizedPlayhead(for: target)) * geo.size.width, y: geo.size.height / 2)
                    .allowsHitTesting(false)

                ForEach(curve.points) { point in
                    Button {
                        selectedPointID = point.id
                    } label: {
                        ZStack {
                            Circle().fill(Color.clear).frame(width: 48, height: 48)
                            Circle()
                                .fill(point.id == selectedPointID ? Color.white : Color.accentColor)
                                .overlay(Circle().stroke(Color.accentColor, lineWidth: 2))
                                .frame(width: point.id == selectedPointID ? 22 : 17, height: point.id == selectedPointID ? 22 : 17)
                        }
                    }
                    .buttonStyle(.plain)
                    .position(x: CGFloat(point.t) * geo.size.width, y: speedY(point.speed, height: geo.size.height))
                }

                if let id = selectedPointID, let point = curve.points.first(where: { $0.id == id }) {
                    VStack {
                        HStack {
                            Text(String(format: "Точка • %.2f× • %.1f%%", point.speed, point.t * 100))
                                .font(.caption2.monospacedDigit().weight(.semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(.ultraThinMaterial, in: Capsule())
                            Spacer()
                        }
                        Spacer()
                    }
                    .padding(8)
                    .allowsHitTesting(false)
                }
            }
            .contentShape(Rectangle())
            .simultaneousGesture(
                DragGesture(minimumDistance: 5, coordinateSpace: .local)
                    .onChanged { value in
                        guard let id = selectedPointID else { return }
                        if !editingCurve {
                            editingCurve = true
                            model.beginCurvePointEdit()
                        }
                        let t = min(max(Double(value.location.x / max(1, geo.size.width)), 0), 1)
                        let speed = ySpeed(value.location.y, height: geo.size.height)
                        model.moveCurvePointInteractive(target, pointID: id, t: t, speed: speed)
                        model.setCurvePlayheadVisual(target, normalized: t)
                    }
                    .onEnded { value in
                        guard selectedPointID != nil, editingCurve else { return }
                        let t = min(max(Double(value.location.x / max(1, geo.size.width)), 0), 1)
                        editingCurve = false
                        model.finishCurvePointEdit(target, normalized: t)
                    }
            )
            .onTapGesture(count: 2) { location in
                let t = min(max(Double(location.x / max(1, geo.size.width)), 0.01), 0.99)
                let speed = ySpeed(location.y, height: geo.size.height)
                model.addCurvePoint(target, t: t, speed: speed)
                model.seekCurveTarget(target, normalized: t)
            }
        }
    }
}
