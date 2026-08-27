import SwiftUI
import PhotosUI

struct LayersPanel: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var project: DesignerProject
    @Binding var selectedID: UUID?
    var body: some View {
        NavigationStack {
            List {
                ForEach(project.elements.indices.reversed(), id: \.self) { i in
                    let e = project.elements[i]
                    HStack {
                        Image(systemName: icon(e.kind))
                        Text(e.name)
                        Spacer()
                        Button { project.elements[i].hidden.toggle() } label: { Image(systemName: e.hidden ? "eye.slash" : "eye") }
                        Button { project.elements[i].locked.toggle() } label: { Image(systemName: e.locked ? "lock.fill" : "lock.open") }
                    }
                    .contentShape(Rectangle()).onTapGesture { selectedID = e.id; dismiss() }
                }
                .onDelete { set in
                    for offset in set { project.elements.remove(at: project.elements.count - 1 - offset) }
                }
            }
            .navigationTitle("Слои")
            .toolbar { Button("Готово") { dismiss() } }
        }
    }
    private func icon(_ k: DesignElement.Kind) -> String { switch k { case .text: "textformat"; case .rectangle:"rectangle"; case .ellipse:"circle"; case .star:"star"; case .image:"photo" } }
}

struct InspectorPanel: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var project: DesignerProject
    @Binding var selectedID: UUID?
    var body: some View {
        NavigationStack {
            Form { InspectorForm(project: $project, selectedID: $selectedID) }
                .navigationTitle("Свойства")
                .toolbar { Button("Готово") { dismiss() } }
        }
    }
}

struct InspectorCompact: View {
    @Binding var project: DesignerProject
    @Binding var selectedID: UUID?
    var body: some View {
        ScrollView { VStack(spacing: 10) { InspectorForm(project: $project, selectedID: $selectedID) }.padding(10) }
            .frame(maxHeight: 290)
    }
}

struct InspectorForm: View {
    @Binding var project: DesignerProject
    @Binding var selectedID: UUID?
    private var index: Int? { project.elements.firstIndex(where: {$0.id == selectedID}) }
    var body: some View {
        if let i = index {
            let kind = project.elements[i].kind
            VStack(alignment: .leading, spacing: 12) {
                Text("Позиция и размер").font(.caption.bold()).foregroundStyle(.secondary)
                HStack { valueField("X", value: $project.elements[i].x); valueField("Y", value: $project.elements[i].y) }
                HStack { valueField("W", value: $project.elements[i].width); valueField("H", value: $project.elements[i].height) }
                HStack { Text("Поворот").font(.caption); Slider(value: $project.elements[i].rotation, in: -180...180) }
                if kind == .text {
                    TextField("Текст", text: $project.elements[i].text).textFieldStyle(.roundedBorder)
                    HStack { Text("Размер").font(.caption); Slider(value: $project.elements[i].fontSize, in: 8...160) }
                }
                Text("Оформление").font(.caption.bold()).foregroundStyle(.secondary)
                HStack { Text("Заливка").font(.caption); TextField("#FFFFFF", text: $project.elements[i].fillHex).textFieldStyle(.roundedBorder) }
                HStack { Text("Обводка").font(.caption); TextField("#FFFFFF", text: $project.elements[i].strokeHex).textFieldStyle(.roundedBorder) }
                HStack { Text("Толщина").font(.caption); Slider(value: $project.elements[i].strokeWidth, in: 0...20) }
                HStack { Text("Непрозрачность").font(.caption); Slider(value: $project.elements[i].opacity, in: 0.05...1) }
                Toggle("Заблокировать", isOn: $project.elements[i].locked)
                Button("Удалить объект", role: .destructive) { project.elements.remove(at: i); selectedID = nil }
            }
        } else {
            Text("Выберите объект на холсте").font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    private func valueField(_ title: String, value: Binding<Double>) -> some View {
        HStack(spacing: 4) { Text(title).font(.caption2).foregroundStyle(.secondary); TextField(title, value: value, format: .number.precision(.fractionLength(2))).textFieldStyle(.roundedBorder) }
    }
}

struct MockupWorkspace: View {
    @Binding var project: DesignerProject
    @Binding var facadeItem: PhotosPickerItem?
    @State private var signScale: CGFloat = 0.65
    @State private var signOffset: CGSize = .zero
    @State private var signRotation: Double = 0
    var body: some View {
        ZStack {
            Color.black
            if let data = project.facadeImageData, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFit()
                signCard.scaleEffect(signScale).offset(signOffset).rotationEffect(.degrees(signRotation))
                    .gesture(DragGesture().onChanged { signOffset = $0.translation })
                    .simultaneousGesture(MagnificationGesture().onChanged { signScale = min(max($0,0.2),2) })
                    .simultaneousGesture(RotationGesture().onChanged { signRotation = $0.degrees })
            } else {
                VStack(spacing: 18) {
                    Image(systemName: "building.2.crop.circle").font(.system(size: 54)).foregroundStyle(.red)
                    Text("Добавьте фото фасада").font(.title2.bold())
                    PhotosPicker(selection: $facadeItem, matching: .images) { Label("Выбрать фото", systemImage: "photo") }.buttonStyle(.borderedProminent).tint(.red)
                }
            }
        }
    }
    private var signCard: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6).fill(Color(hex: project.backgroundHex))
            VStack(spacing: 2) {
                Text(project.elements.first(where: {$0.kind == .text})?.text ?? project.name).font(.system(size: 34, weight: .black)).foregroundStyle(.red)
                if let second = project.elements.filter({$0.kind == .text}).dropFirst().first { Text(second.text).font(.caption.bold()).tracking(3) }
            }
        }.frame(width: 360, height: max(80, 360 / CGFloat(project.widthMM / max(project.heightMM,1)))).shadow(radius: 12)
    }
}

struct ThreeDWorkspace: View {
    let project: DesignerProject
    @State private var angle = -18.0
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            ZStack {
                RoundedRectangle(cornerRadius: 14).fill(Color(white: 0.08)).frame(width: 420, height: 190)
                    .shadow(color: .red.opacity(0.18), radius: 30)
                VStack(spacing: 4) {
                    Text(project.elements.first(where: {$0.kind == .text})?.text ?? "COLORIZE").font(.system(size: 54, weight: .black)).foregroundStyle(.red)
                    Text("3D SIGN PREVIEW").font(.caption.bold()).tracking(5)
                }
            }
            .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
            Slider(value: $angle, in: -45...45).frame(maxWidth: 360)
            Text("Глубина: \(Int(project.depthMM)) мм · \(project.material.rawValue)").foregroundStyle(.secondary)
            Spacer()
        }.frame(maxWidth: .infinity).background(Color(white:0.025))
    }
}

struct ProductionWorkspace: View {
    @Binding var project: DesignerProject
    var area: Double { project.widthMM * project.heightMM / 1_000_000 }
    var ledCount: Int { max(0, Int(area * 32)) }
    var power: Int { Int(Double(ledCount) * 0.72) }
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                productionCard("Конструкция", "Размер \(Int(project.widthMM)) × \(Int(project.heightMM)) мм", "ruler")
                VStack(alignment:.leading, spacing:12) {
                    Text("Материал").font(.headline)
                    Picker("Материал", selection: $project.material) { ForEach(MaterialKind.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented)
                    HStack { Text("Глубина"); Slider(value: $project.depthMM, in: 20...150); Text("\(Int(project.depthMM)) мм").monospacedDigit() }
                }.panel()
                VStack(alignment:.leading, spacing:10) {
                    Text("LED расчёт").font(.headline)
                    Toggle("Подсветка", isOn: $project.ledEnabled)
                    if project.ledEnabled {
                        metric("LED модули", "≈ \(ledCount) шт")
                        metric("Мощность", "≈ \(power) W")
                        metric("Блок питания", "≈ \(max(60, Int(Double(power) * 1.25))) W")
                    }
                }.panel()
            }.padding()
        }.background(Color(white:0.025))
    }
    private func productionCard(_ title:String,_ detail:String,_ icon:String)->some View { HStack { Image(systemName:icon).font(.title); VStack(alignment:.leading){Text(title).font(.headline);Text(detail).foregroundStyle(.secondary)};Spacer() }.panel() }
    private func metric(_ a:String,_ b:String)->some View { HStack{Text(a);Spacer();Text(b).bold()} }
}

struct CostWorkspace: View {
    let project: DesignerProject
    var area: Double { project.widthMM * project.heightMM / 1_000_000 }
    var materialCost: Int { Int(area * 12000) }
    var leds: Int { project.ledEnabled ? Int(area * 32) * 120 : 0 }
    var work: Int { Int(area * 18000) }
    var total: Int { materialCost + leds + work }
    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                Text("Расчёт стоимости").font(.title2.bold()).frame(maxWidth:.infinity,alignment:.leading)
                cost("Материал", materialCost)
                cost("LED", leds)
                cost("Работа", work)
                Divider()
                cost("Себестоимость", total, bold:true)
                cost("Цена клиенту", Int(Double(total) * 1.55), bold:true)
                cost("Прибыль", Int(Double(total) * 0.55), bold:true, accent:true)
            }.panel().padding()
        }.background(Color(white:0.025))
    }
    private func cost(_ title:String,_ value:Int,bold:Bool=false,accent:Bool=false)->some View { HStack{Text(title).fontWeight(bold ? .bold : .regular);Spacer();Text("\(value) ₸").fontWeight(bold ? .bold : .regular).foregroundStyle(accent ? .green : .primary)} }
}

struct ExportWorkspace: View {
    let project: DesignerProject
    @State private var format = "PDF"
    @State private var bleed = true
    @State private var crop = true
    @State private var cmyk = true
    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            VStack(alignment:.leading,spacing:16) {
                Text("Экспорт").font(.title2.bold())
                Picker("Формат", selection: $format) { ForEach(["PNG","PDF","SVG","DXF"], id:\.self) { Text($0) } }.pickerStyle(.segmented)
                HStack { Text("Размер"); Spacer(); Text("1:1 · \(Int(project.widthMM)) × \(Int(project.heightMM)) мм").foregroundStyle(.secondary) }
                Toggle("Добавить вылеты (bleed)", isOn: $bleed)
                Toggle("Метки реза", isOn: $crop)
                Toggle("Цветовой профиль CMYK", isOn: $cmyk)
                Button { } label: { Text("Экспортировать").frame(maxWidth:.infinity) }.buttonStyle(.borderedProminent).tint(.red)
            }.panel().frame(maxWidth:560)
            Spacer()
        }.frame(maxWidth:.infinity).padding().background(Color(white:0.025))
    }
}

extension View {
    func panel() -> some View { self.padding(16).background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 16)).overlay(RoundedRectangle(cornerRadius:16).stroke(Color.white.opacity(0.08))) }
}
