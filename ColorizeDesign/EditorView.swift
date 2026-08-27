import SwiftUI
import PhotosUI

struct EditorView: View {
    @Binding var project: SignProject
    @State private var selectedID: UUID?
    @State private var showLayers = false
    @State private var showInspector = false
    @State private var showMockup = false
    @State private var showGrid = true
    @State private var imagePickerItem: PhotosPickerItem?
    @State private var facadePickerItem: PhotosPickerItem?
    @State private var facadeImage: UIImage?

    var body: some View {
        VStack(spacing: 0) {
            topInfo
            GeometryReader { geo in
                let canvasSize = fittedSize(in: geo.size)
                ZStack {
                    Color(.systemGroupedBackground)
                    ZStack {
                        Color(hex: project.backgroundHex)
                        if showGrid { GridOverlay(columns: 6, rows: 4) }
                        ForEach($project.elements) { $el in elementView($el, canvasSize) }
                    }
                    .frame(width: canvasSize.width, height: canvasSize.height)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .shadow(radius: 8, y: 3)
                    .overlay(alignment: .topLeading) {
                        Text("\(Int(project.widthCM)) × \(Int(project.heightCM)) см")
                            .font(.caption2.monospacedDigit()).padding(6)
                            .background(.ultraThinMaterial, in: Capsule()).offset(y: -30)
                    }
                }
            }
            bottomToolbar
        }
        .navigationTitle(project.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showLayers) { LayersView(project: $project, selectedID: $selectedID) }
        .sheet(isPresented: $showInspector) { InspectorView(project: $project, selectedID: $selectedID) }
        .sheet(isPresented: $showMockup) { FacadeMockupView(facadeImage: facadeImage, project: project) }
        .onChange(of: imagePickerItem) { _, newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self) {
                    await MainActor.run { addImage(data) }
                }
            }
        }
        .onChange(of: facadePickerItem) { _, newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    await MainActor.run { facadeImage = image; showMockup = true }
                }
            }
        }
    }

    private var topInfo: some View {
        HStack(spacing: 14) {
            Label(project.type.rawValue, systemImage: "ruler")
            Spacer()
            Button { showGrid.toggle() } label: { Image(systemName: showGrid ? "grid" : "square") }
            PhotosPicker(selection: $facadePickerItem, matching: .images) { Image(systemName: "building.2") }
            Button { showMockup = true } label: { Image(systemName: "viewfinder") }
        }
        .font(.caption).padding(.horizontal).frame(height: 40).background(.bar)
    }

    private var bottomToolbar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 22) {
                Button { addText() } label: { tool("Текст", "textformat") }
                Button { addRect() } label: { tool("Фигура", "square") }
                PhotosPicker(selection: $imagePickerItem, matching: .images) { tool("Фото", "photo") }
                Button { showLayers = true } label: { tool("Слои", "square.3.layers.3d") }
                Button { showInspector = true } label: { tool("Свойства", "slider.horizontal.3") }
                Button { showMockup = true } label: { tool("Mockup", "building.2.crop.circle") }
                Button { } label: { tool("AI", "sparkles") }
            }
            .padding(.horizontal, 18)
        }
        .padding(.vertical, 8).frame(maxWidth: .infinity).background(.bar)
    }

    private func tool(_ title: String, _ icon: String) -> some View {
        VStack(spacing: 3) { Image(systemName: icon).font(.title3); Text(title).font(.caption2) }
    }

    @ViewBuilder
    private func elementView(_ el: Binding<CanvasElement>, _ size: CGSize) -> some View {
        let e = el.wrappedValue
        Group {
            switch e.kind {
            case .text:
                Text(e.text.isEmpty ? "Текст" : e.text)
                    .font(.system(size: max(12, e.fontSize * size.width / 700), weight: .bold))
                    .foregroundStyle(Color(hex: e.fillHex)).minimumScaleFactor(0.2).lineLimit(2)
                    .frame(width: max(40, e.width * size.width), height: max(28, e.height * size.height))
            case .rectangle:
                RoundedRectangle(cornerRadius: 6).fill(Color(hex: e.fillHex))
                    .frame(width: max(30, e.width * size.width), height: max(24, e.height * size.height))
            case .image:
                if let data = e.imageData, let uiImage = UIImage(data: data) {
                    Image(uiImage: uiImage).resizable().scaledToFit()
                        .frame(width: max(40, e.width * size.width), height: max(40, e.height * size.height))
                } else {
                    RoundedRectangle(cornerRadius: 8).fill(.secondary.opacity(0.15))
                        .frame(width: 80, height: 80).overlay(Image(systemName: "photo"))
                }
            }
        }
        .opacity(e.opacity)
        .scaleEffect(e.scale)
        .overlay {
            if selectedID == e.id {
                RoundedRectangle(cornerRadius: 6).stroke(.blue, style: StrokeStyle(lineWidth: 2, dash: [5]))
            }
        }
        .position(x: e.x * size.width, y: e.y * size.height)
        .rotationEffect(.degrees(e.rotation))
        .gesture(DragGesture().onChanged { value in
            selectedID = e.id
            el.x.wrappedValue = min(max(value.location.x / size.width, 0), 1)
            el.y.wrappedValue = min(max(value.location.y / size.height, 0), 1)
        })
        .simultaneousGesture(MagnificationGesture().onChanged { value in
            selectedID = e.id
            el.scale.wrappedValue = min(max(value, 0.2), 4.0)
        })
        .simultaneousGesture(RotationGesture().onChanged { angle in
            selectedID = e.id
            el.rotation.wrappedValue = angle.degrees
        })
        .onTapGesture { selectedID = e.id }
    }

    private func fittedSize(in available: CGSize) -> CGSize {
        let pad: CGFloat = 44
        let w = max(available.width - pad, 100)
        let h = max(available.height - pad, 100)
        let ratio = project.widthCM / max(project.heightCM, 1)
        if w / h > ratio { return CGSize(width: h * ratio, height: h) }
        return CGSize(width: w, height: w / ratio)
    }

    private func addText() {
        let e = CanvasElement(kind: .text, text: "Новый текст", x: 0.5, y: 0.5, width: 0.45, height: 0.2, fillHex: "#111111", fontSize: 48)
        project.elements.append(e); selectedID = e.id; showInspector = true
    }

    private func addRect() {
        let e = CanvasElement(kind: .rectangle, x: 0.5, y: 0.5, width: 0.3, height: 0.28, fillHex: "#FFCC00")
        project.elements.append(e); selectedID = e.id
    }

    private func addImage(_ data: Data) {
        let e = CanvasElement(kind: .image, imageData: data, x: 0.5, y: 0.5, width: 0.45, height: 0.45)
        project.elements.append(e); selectedID = e.id
    }
}
