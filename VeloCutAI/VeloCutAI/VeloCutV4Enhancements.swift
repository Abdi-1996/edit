import SwiftUI
import AVKit
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
    @State private var anchor: CGFloat?

    var body: some View {
        Capsule()
            .fill(Color.secondary.opacity(0.55))
            .frame(width: 30, height: 5)
            .contentShape(Rectangle().inset(by: -12))
            .highPriorityGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if anchor == nil { anchor = height }
                        let newHeight = min(max((anchor ?? height) + value.translation.height, 38), 120)
                        onChange(newHeight)
                    }
                    .onEnded { _ in anchor = nil }
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
    @State private var anchor: Double?

    var body: some View {
        Capsule()
            .fill(Color.white.opacity(0.95))
            .overlay(Capsule().stroke(Color.accentColor.opacity(0.65), lineWidth: 1))
            .frame(width: 12, height: max(28, height))
            .contentShape(Rectangle().inset(by: -10))
            .highPriorityGesture(
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
            .highPriorityGesture(
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

struct InlineCurveEditorV4: View {
    @ObservedObject var model: EditorViewModel
    let target: CurveTarget
    let onOpen: () -> Void
    @State private var selectedPointID: UUID?

    var body: some View {
        GeometryReader { geo in
            let curve = model.curve(for: target)
            let spaceName = "inline-\(target.id)"

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
                .allowsHitTesting(false)

                Rectangle()
                    .fill(Color.red.opacity(0.9))
                    .frame(width: 1.5)
                    .position(x: CGFloat(model.normalizedPlayhead(for: target)) * geo.size.width, y: geo.size.height / 2)
                    .allowsHitTesting(false)

                ForEach(curve.points) { point in
                    Circle()
                        .fill(point.id == selectedPointID ? Color.white : Color.accentColor)
                        .overlay(Circle().stroke(Color.accentColor, lineWidth: 1.5))
                        .frame(width: point.id == selectedPointID ? 15 : 12, height: point.id == selectedPointID ? 15 : 12)
                        .position(x: CGFloat(point.t) * geo.size.width, y: speedY(point.speed, height: geo.size.height))
                        .contentShape(Rectangle().inset(by: -12))
                        .onTapGesture { selectedPointID = point.id }
                        .highPriorityGesture(
                            DragGesture(minimumDistance: 0, coordinateSpace: .named(spaceName))
                                .onChanged { value in
                                    selectedPointID = point.id
                                    let t = min(max(Double(value.location.x / max(1, geo.size.width)), 0), 1)
                                    let speed = ySpeed(value.location.y, height: geo.size.height)
                                    model.moveCurvePoint(target, pointID: point.id, t: t, speed: speed)
                                    model.seekCurveTarget(target, normalized: t)
                                }
                        )
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
            .coordinateSpace(name: spaceName)
            .contentShape(Rectangle())
            .onTapGesture(count: 2, coordinateSpace: .named(spaceName)) { location in
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
            let curve = model.curve(for: target)
            let spaceName = "curve-editor-\(target.id)"

            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.secondary.opacity(0.08))

                Canvas { context, size in
                    for speed in [0.1, 0.25, 0.5, 1, 2, 5, 10, 20] as [Double] {
                        let y = speedY(speed, height: size.height)
                        var p = Path()
                        p.move(to: CGPoint(x: 0, y: y))
                        p.addLine(to: CGPoint(x: size.width, y: y))
                        context.stroke(p, with: .color(speed == 1 ? .secondary.opacity(0.45) : .secondary.opacity(0.16)), lineWidth: speed == 1 ? 1.2 : 0.6)
                        let label = context.resolve(Text("\(speed, specifier: "%g")×").font(.system(size: 8, design: .monospaced)).foregroundStyle(.secondary))
                        context.draw(label, at: CGPoint(x: 5, y: y - 2), anchor: .bottomLeading)
                    }

                    var path = Path()
                    for i in 0...160 {
                        let t = Double(i) / 160
                        let point = CGPoint(x: CGFloat(t) * size.width, y: speedY(curve.value(at: t), height: size.height))
                        if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
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
                    Circle()
                        .fill(point.id == selectedPointID ? Color.white : Color.accentColor)
                        .overlay(Circle().stroke(Color.accentColor, lineWidth: 2))
                        .frame(width: point.id == selectedPointID ? 20 : 16, height: point.id == selectedPointID ? 20 : 16)
                        .position(x: CGFloat(point.t) * geo.size.width, y: speedY(point.speed, height: geo.size.height))
                        .contentShape(Rectangle().inset(by: -14))
                        .onTapGesture { selectedPointID = point.id }
                        .highPriorityGesture(
                            DragGesture(minimumDistance: 0, coordinateSpace: .named(spaceName))
                                .onChanged { value in
                                    selectedPointID = point.id
                                    let t = min(max(Double(value.location.x / max(1, geo.size.width)), 0), 1)
                                    let speed = ySpeed(value.location.y, height: geo.size.height)
                                    model.moveCurvePoint(target, pointID: point.id, t: t, speed: speed)
                                    model.seekCurveTarget(target, normalized: t)
                                }
                        )
                }
            }
            .coordinateSpace(name: spaceName)
            .contentShape(Rectangle())
            .onTapGesture(count: 2, coordinateSpace: .named(spaceName)) { location in
                let t = min(max(Double(location.x / max(1, geo.size.width)), 0.01), 0.99)
                let speed = ySpeed(location.y, height: geo.size.height)
                model.addCurvePoint(target, t: t, speed: speed)
                model.seekCurveTarget(target, normalized: t)
            }
        }
    }
}