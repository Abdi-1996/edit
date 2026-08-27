import SwiftUI
import UIKit

struct CanvasWorkspace: View {
    @Binding var project: SignProject
    @Binding var selectedID: UUID?
    let showGrid: Bool
    let showRulers: Bool
    let snapping: Bool
    let onBeginChange: () -> Void
    let onEndChange: () -> Void

    @State private var zoom: CGFloat = 1
    @State private var lastZoom: CGFloat = 1

    var body: some View {
        GeometryReader { geo in
            let available = CGSize(width: max(100, geo.size.width - (showRulers ? 30 : 0)), height: max(100, geo.size.height - (showRulers ? 26 : 0)))
            let base = fittedSize(in: available)

            ZStack(alignment: .topLeading) {
                Color(red: 0.095, green: 0.095, blue: 0.11)
                    .contentShape(Rectangle())
                    .onTapGesture { selectedID = nil }

                if showRulers { RulerOverlay().allowsHitTesting(false) }

                ZStack {
                    Color(hex: project.backgroundHex)
                    if showGrid { GridOverlay().allowsHitTesting(false) }
                    ForEach($project.objects) { $object in
                        if !object.isHidden {
                            EditableObjectView(object: $object, selectedID: $selectedID, canvasSize: base, snapping: snapping, onBeginChange: onBeginChange, onEndChange: onEndChange)
                        }
                    }
                }
                .frame(width: base.width, height: base.height)
                .coordinateSpace(name: "canvas")
                .clipped()
                .overlay(RoundedRectangle(cornerRadius: 2).stroke(.white.opacity(0.25), lineWidth: 0.8))
                .shadow(color: .black.opacity(0.45), radius: 14, y: 8)
                .scaleEffect(zoom)
                .position(x: geo.size.width / 2, y: geo.size.height / 2)
                .gesture(
                    MagnificationGesture()
                        .onChanged { value in zoom = min(max(lastZoom * value, 0.25), 6) }
                        .onEnded { _ in lastZoom = zoom }
                )

                VStack { Spacer(); HStack { Spacer(); Text("\(Int(zoom * 100))%  ·  \(Int(project.widthCM)) × \(Int(project.heightCM)) см").font(.caption2.monospacedDigit()).padding(.horizontal, 9).padding(.vertical, 5).background(.ultraThinMaterial, in: Capsule()).padding(10) } }
                    .allowsHitTesting(false)
            }
        }
    }

    private func fittedSize(in available: CGSize) -> CGSize {
        let ratio = CGFloat(project.widthCM / max(project.heightCM, 1))
        let w = available.width * 0.82
        let h = available.height * 0.72
        if w / h > ratio { return CGSize(width: h * ratio, height: h) }
        return CGSize(width: w, height: w / ratio)
    }
}

struct EditableObjectView: View {
    @Binding var object: CanvasObject
    @Binding var selectedID: UUID?
    let canvasSize: CGSize
    let snapping: Bool
    let onBeginChange: () -> Void
    let onEndChange: () -> Void
    @State private var changing = false
    @State private var scaleStartWidth: Double?
    @State private var scaleStartHeight: Double?
    @State private var rotationStart: Double?

    var isSelected: Bool { selectedID == object.id }

    var body: some View {
        objectContent
            .opacity(object.opacity)
            .frame(width: max(24, object.width * canvasSize.width), height: max(20, object.height * canvasSize.height))
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(Color.purple, style: StrokeStyle(lineWidth: 1.5, dash: [5,3]))
                        .overlay(alignment: .bottomTrailing) { Circle().fill(Color.white).frame(width: 10, height: 10).overlay(Circle().stroke(Color.purple, lineWidth: 2)).offset(x: 5, y: 5) }
                }
            }
            .position(x: object.x * canvasSize.width, y: object.y * canvasSize.height)
            .rotationEffect(.degrees(object.rotation))
            .contentShape(Rectangle())
            .onTapGesture { selectedID = object.id }
            .gesture(dragGesture)
            .simultaneousGesture(MagnificationGesture().onChanged { value in
                guard !object.isLocked else { return }
                beginIfNeeded()
                if scaleStartWidth == nil { scaleStartWidth = object.width; scaleStartHeight = object.height }
                object.width = min(max((scaleStartWidth ?? object.width) * Double(value), 0.02), 1.5)
                object.height = min(max((scaleStartHeight ?? object.height) * Double(value), 0.02), 1.5)
            }.onEnded { _ in scaleStartWidth = nil; scaleStartHeight = nil; finishChange() })
            .simultaneousGesture(RotationGesture().onChanged { angle in
                guard !object.isLocked else { return }
                beginIfNeeded()
                if rotationStart == nil { rotationStart = object.rotation }
                object.rotation = (rotationStart ?? 0) + angle.degrees
            }.onEnded { _ in rotationStart = nil; finishChange() })
    }

    @ViewBuilder
    private var objectContent: some View {
        switch object.kind {
        case .text:
            Text(object.text.isEmpty ? "Текст" : object.text)
                .font(.system(size: max(9, object.fontSize * canvasSize.width / 850), weight: weight))
                .tracking(object.letterSpacing)
                .foregroundStyle(Color(hex: object.fillHex))
                .minimumScaleFactor(0.1).lineLimit(3).multilineTextAlignment(.center)
        case .rectangle:
            RoundedRectangle(cornerRadius: object.cornerRadius)
                .fill(Color(hex: object.fillHex))
                .overlay(RoundedRectangle(cornerRadius: object.cornerRadius).stroke(Color(hex: object.strokeHex), lineWidth: object.strokeWidth))
        case .ellipse:
            Ellipse().fill(Color(hex: object.fillHex)).overlay(Ellipse().stroke(Color(hex: object.strokeHex), lineWidth: object.strokeWidth))
        case .image:
            if let data = object.imageData, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFit()
            } else {
                Rectangle().fill(.secondary.opacity(0.15)).overlay(Image(systemName: "photo"))
            }
        case .line:
            Rectangle().fill(Color(hex: object.fillHex)).frame(height: max(1, object.strokeWidth))
        }
    }

    private var weight: Font.Weight {
        switch object.fontWeight {
        case "black": return .black
        case "semibold": return .semibold
        case "medium": return .medium
        case "regular": return .regular
        default: return .bold
        }
    }

    private var dragGesture: some Gesture {
        DragGesture(coordinateSpace: .named("canvas"))
            .onChanged { value in
                guard !object.isLocked else { return }
                beginIfNeeded(); selectedID = object.id
                var nx = min(max(value.location.x / canvasSize.width, 0), 1)
                var ny = min(max(value.location.y / canvasSize.height, 0), 1)
                if snapping {
                    if abs(nx - 0.5) < 0.022 { nx = 0.5 }
                    if abs(ny - 0.5) < 0.022 { ny = 0.5 }
                    if abs(nx - 0.25) < 0.015 { nx = 0.25 }
                    if abs(nx - 0.75) < 0.015 { nx = 0.75 }
                }
                object.x = nx; object.y = ny
            }
            .onEnded { _ in finishChange() }
    }

    private func beginIfNeeded() {
        if !changing { changing = true; onBeginChange() }
    }
    private func finishChange() {
        if changing { changing = false; onEndChange() }
    }
}

struct GridOverlay: View {
    var body: some View {
        GeometryReader { geo in
            Path { path in
                for i in 1..<12 {
                    let x = geo.size.width * CGFloat(i) / 12
                    path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: geo.size.height))
                }
                for i in 1..<8 {
                    let y = geo.size.height * CGFloat(i) / 8
                    path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: geo.size.width, y: y))
                }
            }.stroke(.black.opacity(0.12), lineWidth: 0.55)
        }
    }
}

struct RulerOverlay: View {
    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle().fill(Color.black.opacity(0.30)).frame(height: 25)
            Rectangle().fill(Color.black.opacity(0.30)).frame(width: 29)
            HStack { Spacer(); ForEach([0,25,50,75,100], id: \.self) { value in Text("\(value)").font(.system(size: 8, design: .monospaced)).foregroundStyle(.secondary); Spacer() } }.padding(.leading, 28).frame(height: 25)
            VStack { Spacer(); ForEach([0,25,50,75,100], id: \.self) { value in Text("\(value)").font(.system(size: 8, design: .monospaced)).foregroundStyle(.secondary).rotationEffect(.degrees(-90)); Spacer() } }.padding(.top, 24).frame(width: 29)
        }
    }
}
