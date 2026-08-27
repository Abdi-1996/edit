import SwiftUI
import PhotosUI
import UIKit

struct InspectorPanel: View {
    @Binding var project: SignProject
    @Binding var selectedID: UUID?
    let onMutation: () -> Void
    @State private var tab = 0

    private var selectedIndex: Int? { project.objects.firstIndex(where: { $0.id == selectedID }) }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Panel", selection: $tab) {
                Text("Layers").tag(0)
                Text("Properties").tag(1)
                Text("Color").tag(2)
            }
            .pickerStyle(.segmented).padding(10)
            Divider().opacity(0.2)
            if tab == 0 { layers }
            else if tab == 1 { properties }
            else { colors }
        }
        .background(Color.black.opacity(0.20))
    }

    private var layers: some View {
        List {
            ForEach(project.objects.indices.reversed(), id: \.self) { index in
                let object = project.objects[index]
                HStack(spacing: 10) {
                    Button { selectedID = object.id } label: {
                        Image(systemName: icon(for: object.kind)).frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(object.name).lineLimit(1)
                            Text(object.kind.rawValue.capitalized).font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .buttonStyle(.plain)
                    Button { onMutation(); project.objects[index].isHidden.toggle() } label: { Image(systemName: object.isHidden ? "eye.slash" : "eye") }.buttonStyle(.plain)
                    Button { onMutation(); project.objects[index].isLocked.toggle() } label: { Image(systemName: object.isLocked ? "lock.fill" : "lock.open") }.buttonStyle(.plain)
                }
                .padding(.vertical, 3)
                .listRowBackground(selectedID == object.id ? Color.purple.opacity(0.20) : Color.clear)
            }
        }
        .listStyle(.plain)
    }

    @ViewBuilder
    private var properties: some View {
        if let index = selectedIndex {
            Form {
                Section("Object") {
                    TextField("Name", text: $project.objects[index].name)
                    if project.objects[index].kind == .text {
                        TextField("Text", text: $project.objects[index].text, axis: .vertical)
                        HStack { Text("Size"); Slider(value: $project.objects[index].fontSize, in: 8...180); Text("\(Int(project.objects[index].fontSize))").monospacedDigit().foregroundStyle(.secondary) }
                        HStack { Text("Tracking"); Slider(value: $project.objects[index].letterSpacing, in: -4...20) }
                    }
                }
                Section("Transform") {
                    HStack { Text("X"); Slider(value: $project.objects[index].x, in: 0...1) }
                    HStack { Text("Y"); Slider(value: $project.objects[index].y, in: 0...1) }
                    HStack { Text("Width"); Slider(value: $project.objects[index].width, in: 0.02...1.2) }
                    HStack { Text("Height"); Slider(value: $project.objects[index].height, in: 0.02...1.2) }
                    HStack { Text("Rotation"); Slider(value: $project.objects[index].rotation, in: -180...180); Text("\(Int(project.objects[index].rotation))°").foregroundStyle(.secondary) }
                    HStack { Text("Opacity"); Slider(value: $project.objects[index].opacity, in: 0...1) }
                }
                Section("Style") {
                    HStack { Text("Stroke"); Slider(value: $project.objects[index].strokeWidth, in: 0...20) }
                    if project.objects[index].kind == .rectangle {
                        HStack { Text("Corners"); Slider(value: $project.objects[index].cornerRadius, in: 0...80) }
                    }
                }
                Section {
                    Button {
                        onMutation()
                        var copy = project.objects[index]; copy.id = UUID(); copy.name += " copy"; copy.x = min(1, copy.x + 0.04); copy.y = min(1, copy.y + 0.04)
                        project.objects.append(copy); selectedID = copy.id
                    } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
                    Button(role: .destructive) { onMutation(); project.objects.remove(at: index); selectedID = nil } label: { Label("Delete", systemImage: "trash") }
                }
            }
        } else {
            ContentUnavailableView("No selection", systemImage: "cursorarrow.click", description: Text("Select an object on canvas or in Layers"))
        }
    }

    @ViewBuilder
    private var colors: some View {
        if let index = selectedIndex {
            Form {
                Section("Fill") {
                    TextField("HEX", text: $project.objects[index].fillHex).textInputAutocapitalization(.characters)
                    HStack(spacing: 10) {
                        ForEach(["#7119E8", "#FF2D55", "#FFCC00", "#00C2FF", "#FFFFFF", "#111111"], id: \.self) { hex in
                            Button { onMutation(); project.objects[index].fillHex = hex } label: { Circle().fill(Color(hex: hex)).frame(width: 30, height: 30).overlay(Circle().stroke(.white.opacity(0.25))) }.buttonStyle(.plain)
                        }
                    }
                }
                Section("Stroke") { TextField("HEX", text: $project.objects[index].strokeHex).textInputAutocapitalization(.characters) }
                Section("Document") { TextField("Canvas HEX", text: $project.backgroundHex).textInputAutocapitalization(.characters) }
            }
        } else {
            Form { Section("Document") { TextField("Canvas HEX", text: $project.backgroundHex).textInputAutocapitalization(.characters) } }
        }
    }

    private func icon(for kind: CanvasObjectKind) -> String {
        switch kind {
        case .text: return "textformat"
        case .rectangle: return "rectangle"
        case .ellipse: return "circle"
        case .image: return "photo"
        case .line: return "line.diagonal"
        }
    }
}

struct WorkspaceHost: View {
    let mode: WorkspaceMode
    @Binding var project: SignProject
    var body: some View {
        switch mode {
        case .mockup: MockupWorkspace(project: project)
        case .preview3D: ThreeDWorkspace(project: project)
        case .production: ProductionWorkspace(project: $project)
        case .cost: CostWorkspace(project: $project)
        case .export: ExportWorkspace(project: project)
        case .design: EmptyView()
        }
    }
}

struct MockupWorkspace: View {
    let project: SignProject
    @State private var photoItem: PhotosPickerItem?
    @State private var facadeImage: UIImage?
    @State private var signScale: CGFloat = 0.62
    @State private var signOffset: CGSize = .zero
    @State private var signRotation: Double = 0
    @State private var night = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()
            if let facadeImage {
                Image(uiImage: facadeImage).resizable().scaledToFit().opacity(night ? 0.48 : 1)
                ProjectPreview(project: project)
                    .frame(width: 420, height: 130)
                    .scaleEffect(signScale)
                    .rotationEffect(.degrees(signRotation))
                    .offset(signOffset)
                    .shadow(color: night ? .purple.opacity(0.75) : .black.opacity(0.35), radius: night ? 22 : 8)
                    .gesture(DragGesture().onChanged { signOffset = $0.translation })
                    .simultaneousGesture(MagnificationGesture().onChanged { signScale = min(max($0, 0.15), 2.0) })
                    .simultaneousGesture(RotationGesture().onChanged { signRotation = $0.degrees })
            } else {
                ContentUnavailableView("Facade mockup", systemImage: "building.2", description: Text("Import a facade photo and position the sign"))
            }
            VStack {
                HStack {
                    PhotosPicker(selection: $photoItem, matching: .images) { Label("Facade photo", systemImage: "photo.badge.plus") }.buttonStyle(.borderedProminent)
                    Toggle("Night", isOn: $night).toggleStyle(.button)
                    Spacer()
                }.padding()
                Spacer()
            }
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task { if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) { await MainActor.run { facadeImage = image } } }
        }
    }
}

struct ThreeDWorkspace: View {
    let project: SignProject
    @State private var depth = 22.0
    @State private var angle = -18.0
    @State private var lightOn = true

    var body: some View {
        VStack(spacing: 20) {
            HStack { Text("3D Sign Preview").font(.title2.bold()); Spacer(); Toggle("LED", isOn: $lightOn).toggleStyle(.switch) }.padding(.horizontal)
            Spacer()
            ZStack {
                ForEach((0..<10).reversed(), id: \.self) { i in
                    ProjectPreview(project: project)
                        .frame(width: 620, height: 180)
                        .offset(x: CGFloat(i) * CGFloat(depth/10), y: CGFloat(i) * CGFloat(depth/18))
                        .opacity(i == 0 ? 1 : 0.22)
                }
                ProjectPreview(project: project)
                    .frame(width: 620, height: 180)
                    .shadow(color: lightOn ? .purple.opacity(0.65) : .black.opacity(0.4), radius: lightOn ? 25 : 8)
            }
            .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0))
            Spacer()
            VStack { HStack { Text("Depth"); Slider(value: $depth, in: 2...80); Text("\(Int(depth)) mm").monospacedDigit() }; HStack { Text("View angle"); Slider(value: $angle, in: -55...55) } }.padding().background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16)).padding()
        }
    }
}

struct ProductionWorkspace: View {
    @Binding var project: SignProject
    var materialWithWaste: Double { project.areaM2 * (1 + project.production.wastePercent / 100) }
    var ledCount: Int { project.production.ledEnabled ? Int(ceil(project.areaM2 * project.production.ledModulesPerM2)) : 0 }
    var watts: Double { Double(ledCount) * project.production.wattsPerModule }
    var powerSupply: Int { project.production.ledEnabled ? Int(ceil(watts * 1.25 / 100.0) * 100) : 0 }

    var body: some View {
        Form {
            Section("Sign") {
                LabeledContent("Size", value: "\(Int(project.widthCM)) × \(Int(project.heightCM)) cm")
                LabeledContent("Area", value: String(format: "%.2f m²", project.areaM2))
                LabeledContent("Type", value: project.signType.rawValue)
            }
            Section("Material") {
                Picker("Material", selection: $project.production.material) { ForEach(MaterialType.allCases) { Text($0.rawValue).tag($0) } }
                HStack { Text("Waste"); Slider(value: $project.production.wastePercent, in: 0...35); Text("\(Int(project.production.wastePercent))%") }
                LabeledContent("Required", value: String(format: "%.2f m²", materialWithWaste))
            }
            Section("LED") {
                Toggle("Illuminated sign", isOn: $project.production.ledEnabled)
                if project.production.ledEnabled {
                    HStack { Text("Modules / m²"); Slider(value: $project.production.ledModulesPerM2, in: 10...90); Text("\(Int(project.production.ledModulesPerM2))") }
                    LabeledContent("LED modules", value: "~\(ledCount)")
                    LabeledContent("Estimated power", value: String(format: "%.0f W", watts))
                    LabeledContent("Recommended PSU", value: "\(powerSupply) W")
                }
            }
        }
    }
}

struct CostWorkspace: View {
    @Binding var project: SignProject
    private var materialArea: Double { project.areaM2 * (1 + project.production.wastePercent/100) }
    private var materialCost: Double { materialArea * project.production.materialPricePerM2 }
    private var subtotal: Double { materialCost + project.production.laborCost + project.production.installationCost }
    private var total: Double { subtotal * (1 + project.production.markupPercent/100) }

    var body: some View {
        Form {
            Section("Pricing") {
                HStack { Text("Material price / m²"); Spacer(); TextField("9000", value: $project.production.materialPricePerM2, format: .number).multilineTextAlignment(.trailing); Text("₸") }
                HStack { Text("Labor"); Spacer(); TextField("15000", value: $project.production.laborCost, format: .number).multilineTextAlignment(.trailing); Text("₸") }
                HStack { Text("Installation"); Spacer(); TextField("12000", value: $project.production.installationCost, format: .number).multilineTextAlignment(.trailing); Text("₸") }
                HStack { Text("Markup"); Slider(value: $project.production.markupPercent, in: 0...120); Text("\(Int(project.production.markupPercent))%") }
            }
            Section("Estimate") {
                LabeledContent("Material", value: money(materialCost))
                LabeledContent("Subtotal", value: money(subtotal))
                LabeledContent("Client price", value: money(total)).font(.headline)
                LabeledContent("Gross margin", value: money(total - subtotal)).foregroundStyle(.green)
            }
        }
    }

    private func money(_ value: Double) -> String { "\(Int(value.rounded())) ₸" }
}

struct ProjectPreview: View {
    let project: SignProject
    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color(hex: project.backgroundHex)
                ForEach(project.objects.filter { !$0.isHidden }) { object in
                    previewObject(object, size: geo.size)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    @ViewBuilder
    private func previewObject(_ object: CanvasObject, size: CGSize) -> some View {
        Group {
            switch object.kind {
            case .text:
                Text(object.text).font(.system(size: max(8, object.fontSize * size.width / 850), weight: .bold)).tracking(object.letterSpacing).foregroundStyle(Color(hex: object.fillHex)).minimumScaleFactor(0.1).lineLimit(2)
            case .rectangle: RoundedRectangle(cornerRadius: object.cornerRadius).fill(Color(hex: object.fillHex))
            case .ellipse: Ellipse().fill(Color(hex: object.fillHex))
            case .image:
                if let data = object.imageData, let image = UIImage(data: data) { Image(uiImage: image).resizable().scaledToFit() } else { Color.clear }
            case .line: Rectangle().fill(Color(hex: object.fillHex))
            }
        }
        .frame(width: object.width * size.width, height: object.height * size.height)
        .position(x: object.x * size.width, y: object.y * size.height)
        .rotationEffect(.degrees(object.rotation)).opacity(object.opacity)
    }
}
