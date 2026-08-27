import SwiftUI
import PhotosUI

private enum EditorTool: String, CaseIterable, Identifiable {
    case move = "Выделение", node = "Узлы", pen = "Перо", pencil = "Карандаш", text = "Текст", shape = "Фигура", image = "Изображение", crop = "Обрезка", gradient = "Градиент", transparency = "Прозрачность", measure = "Измерение"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .move: "arrow.up.left.and.arrow.down.right"
        case .node: "point.3.connected.trianglepath.dotted"
        case .pen: "pencil.and.outline"
        case .pencil: "pencil"
        case .text: "textformat"
        case .shape: "square.on.circle"
        case .image: "photo"
        case .crop: "crop"
        case .gradient: "circle.lefthalf.filled"
        case .transparency: "circle.dotted"
        case .measure: "ruler"
        }
    }
}

private enum WorkspaceMode: String, CaseIterable, Identifiable {
    case design = "Дизайн", mockup = "Mockup", view3D = "3D", production = "Производство", cost = "Расчёт", export = "Экспорт"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .design: "square.grid.2x2"
        case .mockup: "building.2"
        case .view3D: "cube"
        case .production: "square.3.layers.3d"
        case .cost: "calculator"
        case .export: "square.and.arrow.up"
        }
    }
}

struct EditorView: View {
    @Binding var project: DesignerProject
    @Environment(\.horizontalSizeClass) private var hSize
    @State private var tool: EditorTool = .move
    @State private var mode: WorkspaceMode = .design
    @State private var selectedID: UUID?
    @State private var showGrid = true
    @State private var showSnapping = true
    @State private var showLayersSheet = false
    @State private var showInspectorSheet = false
    @State private var photoItem: PhotosPickerItem?
    @State private var facadeItem: PhotosPickerItem?
    @State private var zoom: CGFloat = 1
    @State private var canvasOffset: CGSize = .zero

    private var isPad: Bool { hSize == .regular }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            if mode == .design { designWorkspace }
            else { modeWorkspace }
            bottomModeBar
        }
        .background(Color.black)
        .navigationBarBackButtonHidden(false)
        .sheet(isPresented: $showLayersSheet) { LayersPanel(project: $project, selectedID: $selectedID) }
        .sheet(isPresented: $showInspectorSheet) { InspectorPanel(project: $project, selectedID: $selectedID) }
        .onChange(of: photoItem) { _, item in importPhoto(item) }
        .onChange(of: facadeItem) { _, item in importFacade(item) }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Text(project.name).font(.headline).lineLimit(1)
            Spacer()
            Button { } label: { Image(systemName: "arrow.uturn.backward") }
            Button { } label: { Image(systemName: "arrow.uturn.forward") }
            if isPad {
                Divider().frame(height: 18)
                Button { showSnapping.toggle() } label: { Label("Привязка", systemImage: "dot.scope") }
                Button { alignSelection() } label: { Label("Выровнять", systemImage: "align.horizontal.center") }
                Button { groupHint() } label: { Label("Группировать", systemImage: "square.on.square") }
            }
            Button { showGrid.toggle() } label: { Image(systemName: "grid") }
            Text("\(Int(zoom * 100))%").font(.caption.monospacedDigit()).frame(width: 44)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .padding(.horizontal, isPad ? 18 : 12)
        .frame(height: isPad ? 54 : 48)
        .background(Color(white: 0.06))
        .overlay(alignment: .bottom) { Divider().opacity(0.35) }
    }

    private var designWorkspace: some View {
        HStack(spacing: 0) {
            if isPad { toolRail }
            canvasArea
            if isPad { rightStudio }
        }
    }

    private var toolRail: some View {
        VStack(spacing: 4) {
            ForEach(EditorTool.allCases) { item in
                Button {
                    tool = item
                    if item == .text { addText() }
                    if item == .shape { addRectangle() }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: item.icon).frame(width: 24)
                        Text(item.rawValue).font(.caption)
                        Spacer()
                    }
                    .padding(.horizontal, 10).frame(height: 42)
                    .background(tool == item ? Color.red.opacity(0.18) : .clear, in: RoundedRectangle(cornerRadius: 9))
                    .foregroundStyle(tool == item ? .red : .primary)
                }
            }
            PhotosPicker(selection: $photoItem, matching: .images) {
                HStack(spacing: 10) { Image(systemName: "photo.badge.plus").frame(width: 24); Text("Импорт фото").font(.caption); Spacer() }
                    .padding(.horizontal, 10).frame(height: 42)
            }
            Spacer()
        }
        .padding(8)
        .frame(width: 170)
        .background(Color(white: 0.055))
        .overlay(alignment: .trailing) { Divider().opacity(0.35) }
    }

    private var canvasArea: some View {
        GeometryReader { geo in
            let base = fittedCanvas(in: geo.size)
            ZStack {
                Color(white: 0.025)
                rulerBackground(size: base)
                ZStack {
                    Color(hex: project.backgroundHex)
                    if showGrid { GridLines() }
                    ForEach($project.elements) { $el in
                        if !el.hidden { elementView($el, canvasSize: base) }
                    }
                }
                .frame(width: base.width, height: base.height)
                .scaleEffect(zoom)
                .offset(canvasOffset)
                .clipShape(Rectangle())
                .overlay(Rectangle().stroke(Color.white.opacity(0.15), lineWidth: 1))
                .gesture(MagnificationGesture().onChanged { value in zoom = min(max(value, 0.35), 5) })
                .simultaneousGesture(DragGesture(minimumDistance: 8).onChanged { value in
                    if selectedID == nil { canvasOffset = value.translation }
                })
            }
        }
    }

    private func rulerBackground(size: CGSize) -> some View {
        ZStack {
            VStack { HStack(spacing: 0) { ForEach(0..<8) { i in Text("\(i * 50)").font(.system(size: 8)).foregroundStyle(.secondary).frame(maxWidth: .infinity) } }.frame(height: 18); Spacer() }
            HStack { VStack(spacing: 0) { ForEach(0..<6) { i in Text("\(i * 50)").font(.system(size: 8)).foregroundStyle(.secondary).frame(maxHeight: .infinity) } }.frame(width: 18); Spacer() }
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder private func elementView(_ el: Binding<DesignElement>, canvasSize: CGSize) -> some View {
        let e = el.wrappedValue
        Group {
            switch e.kind {
            case .text:
                Text(e.text)
                    .font(.system(size: max(12, e.fontSize * canvasSize.width / 900), weight: .black))
                    .foregroundStyle(Color(hex: e.fillHex))
                    .minimumScaleFactor(0.15).lineLimit(2)
                    .frame(width: max(30, e.width * canvasSize.width), height: max(24, e.height * canvasSize.height))
            case .rectangle:
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(hex: e.fillHex))
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(hex: e.strokeHex), lineWidth: e.strokeWidth))
                    .frame(width: max(25, e.width * canvasSize.width), height: max(25, e.height * canvasSize.height))
            case .ellipse:
                Ellipse().fill(Color(hex: e.fillHex)).frame(width: e.width * canvasSize.width, height: e.height * canvasSize.height)
            case .star:
                Image(systemName: "star.fill").resizable().foregroundStyle(Color(hex: e.fillHex)).frame(width: e.width * canvasSize.width, height: e.height * canvasSize.height)
            case .image:
                if let data = e.imageData, let image = UIImage(data: data) {
                    Image(uiImage: image).resizable().scaledToFit().frame(width: e.width * canvasSize.width, height: e.height * canvasSize.height)
                }
            }
        }
        .opacity(e.opacity)
        .overlay {
            if selectedID == e.id {
                Rectangle().stroke(.cyan, style: StrokeStyle(lineWidth: 1.5, dash: [4,3]))
                    .overlay(alignment: .topLeading) { handle }
                    .overlay(alignment: .topTrailing) { handle }
                    .overlay(alignment: .bottomLeading) { handle }
                    .overlay(alignment: .bottomTrailing) { handle }
            }
        }
        .position(x: e.x * canvasSize.width, y: e.y * canvasSize.height)
        .rotationEffect(.degrees(e.rotation))
        .gesture(DragGesture().onChanged { value in
            guard !e.locked else { return }
            selectedID = e.id
            el.x.wrappedValue = min(max(value.location.x / canvasSize.width, 0), 1)
            el.y.wrappedValue = min(max(value.location.y / canvasSize.height, 0), 1)
        })
        .simultaneousGesture(RotationGesture().onChanged { a in if !e.locked { el.rotation.wrappedValue = a.degrees } })
        .onTapGesture { selectedID = e.id }
    }

    private var handle: some View { Circle().fill(.white).stroke(.cyan, lineWidth: 1.5).frame(width: 9, height: 9).offset(x: -4, y: -4) }

    private var rightStudio: some View {
        VStack(spacing: 0) {
            HStack { Text("Слои").font(.headline); Spacer(); Button { addLayerMenu() } label: { Image(systemName: "plus") } }.padding(12)
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(project.elements.indices.reversed(), id: \.self) { i in
                        let e = project.elements[i]
                        HStack(spacing: 8) {
                            Image(systemName: iconFor(e.kind)).frame(width: 22)
                            Text(e.name).font(.caption).lineLimit(1)
                            Spacer()
                            Button { project.elements[i].hidden.toggle() } label: { Image(systemName: e.hidden ? "eye.slash" : "eye") }
                            Button { project.elements[i].locked.toggle() } label: { Image(systemName: e.locked ? "lock.fill" : "lock.open") }
                        }
                        .padding(.horizontal, 8).frame(height: 38)
                        .background(selectedID == e.id ? Color.red.opacity(0.15) : .clear, in: RoundedRectangle(cornerRadius: 7))
                        .contentShape(Rectangle()).onTapGesture { selectedID = e.id }
                    }
                }.padding(8)
            }
            Divider()
            InspectorCompact(project: $project, selectedID: $selectedID)
        }
        .frame(width: 260)
        .background(Color(white: 0.055))
        .overlay(alignment: .leading) { Divider().opacity(0.35) }
    }

    private var bottomModeBar: some View {
        HStack(spacing: 4) {
            if !isPad {
                Button { showLayersSheet = true } label: { bottomItem("Слои", "square.3.layers.3d", active: false) }
                Button { addText() } label: { bottomItem("Текст", "textformat", active: false) }
                PhotosPicker(selection: $photoItem, matching: .images) { bottomItem("Фото", "photo", active: false) }
            }
            ForEach(WorkspaceMode.allCases) { item in
                if isPad || item != .design {
                    Button { mode = item } label: { bottomItem(item.rawValue, item.icon, active: mode == item) }
                }
            }
            if !isPad { Button { showInspectorSheet = true } label: { bottomItem("Свойства", "slider.horizontal.3", active: false) } }
        }
        .padding(.horizontal, 6).frame(height: isPad ? 58 : 64)
        .background(Color(white: 0.065))
        .overlay(alignment: .top) { Divider().opacity(0.35) }
    }

    private func bottomItem(_ title: String, _ icon: String, active: Bool) -> some View {
        VStack(spacing: 4) { Image(systemName: icon); Text(title).font(.system(size: isPad ? 11 : 9)) }
            .foregroundStyle(active ? .red : .primary).frame(maxWidth: .infinity)
    }

    @ViewBuilder private var modeWorkspace: some View {
        switch mode {
        case .mockup: MockupWorkspace(project: $project, facadeItem: $facadeItem)
        case .view3D: ThreeDWorkspace(project: project)
        case .production: ProductionWorkspace(project: $project)
        case .cost: CostWorkspace(project: project)
        case .export: ExportWorkspace(project: project)
        case .design: EmptyView()
        }
    }

    private func fittedCanvas(in available: CGSize) -> CGSize {
        let ratio = project.widthMM / max(project.heightMM, 1)
        let w = max(available.width - 42, 100); let h = max(available.height - 42, 100)
        if w / h > ratio { return CGSize(width: h * ratio, height: h) }
        return CGSize(width: w, height: w / ratio)
    }

    private func addText() {
        let e = DesignElement(kind: .text, name: "Новый текст", text: "Новый текст", x: 0.5, y: 0.5, width: 0.42, height: 0.18, fillHex: "#FFFFFF", fontSize: 52)
        project.elements.append(e); selectedID = e.id; tool = .move
    }
    private func addRectangle() {
        let e = DesignElement(kind: .rectangle, name: "Прямоугольник", x: 0.5, y: 0.5, width: 0.28, height: 0.24, fillHex: "#FF0000")
        project.elements.append(e); selectedID = e.id; tool = .move
    }
    private func addLayerMenu() { addRectangle() }
    private func alignSelection() { if let i = project.elements.firstIndex(where: {$0.id == selectedID}) { project.elements[i].x = 0.5 } }
    private func groupHint() { }

    private func importPhoto(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            if let data = try? await item.loadTransferable(type: Data.self) {
                await MainActor.run {
                    let e = DesignElement(kind: .image, name: "Изображение", imageData: data, x: 0.5, y: 0.5, width: 0.45, height: 0.45)
                    project.elements.append(e); selectedID = e.id; tool = .move
                }
            }
        }
    }
    private func importFacade(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task { if let data = try? await item.loadTransferable(type: Data.self) { await MainActor.run { project.facadeImageData = data } } }
    }

    private func iconFor(_ kind: DesignElement.Kind) -> String {
        switch kind { case .text: "textformat"; case .rectangle: "rectangle"; case .ellipse: "circle"; case .star: "star"; case .image: "photo" }
    }
}

struct GridLines: View {
    var body: some View {
        GeometryReader { geo in
            Path { p in
                for i in 1..<8 { let x = geo.size.width * CGFloat(i) / 8; p.move(to: .init(x:x,y:0)); p.addLine(to:.init(x:x,y:geo.size.height)) }
                for i in 1..<5 { let y = geo.size.height * CGFloat(i) / 5; p.move(to:.init(x:0,y:y)); p.addLine(to:.init(x:geo.size.width,y:y)) }
            }.stroke(Color.white.opacity(0.08), lineWidth: 0.5)
        }.allowsHitTesting(false)
    }
}
