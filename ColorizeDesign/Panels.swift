import SwiftUI

struct LayersView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var project: SignProject
    @Binding var selectedID: UUID?

    var body: some View {
        NavigationStack {
            List {
                ForEach(project.elements.indices.reversed(), id: \.self) { i in
                    let el = project.elements[i]
                    Button {
                        selectedID = el.id; dismiss()
                    } label: {
                        HStack {
                            Image(systemName: icon(for: el.kind))
                            Text(title(for: el))
                            Spacer()
                            if selectedID == el.id { Image(systemName: "checkmark") }
                        }
                    }
                }
                .onDelete { set in
                    for offset in set { project.elements.remove(at: project.elements.count - 1 - offset) }
                }
            }
            .navigationTitle("Слои")
            .toolbar { Button("Готово") { dismiss() } }
        }
    }

    private func icon(for kind: CanvasElement.Kind) -> String {
        switch kind { case .text: return "textformat"; case .rectangle: return "square.fill"; case .image: return "photo" }
    }
    private func title(for el: CanvasElement) -> String {
        switch el.kind { case .text: return el.text.isEmpty ? "Текст" : el.text; case .rectangle: return "Фигура"; case .image: return "Изображение" }
    }
}

struct InspectorView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var project: SignProject
    @Binding var selectedID: UUID?
    var selectedIndex: Int? { project.elements.firstIndex(where: { $0.id == selectedID }) }

    var body: some View {
        NavigationStack {
            Form {
                if let i = selectedIndex {
                    if project.elements[i].kind == .text {
                        Section("Текст") {
                            TextField("Текст", text: $project.elements[i].text)
                            HStack { Text("Размер"); Slider(value: $project.elements[i].fontSize, in: 12...140) }
                        }
                    }
                    Section("Трансформация") {
                        HStack { Text("Ширина"); Slider(value: $project.elements[i].width, in: 0.05...0.95) }
                        HStack { Text("Высота"); Slider(value: $project.elements[i].height, in: 0.05...0.95) }
                        HStack { Text("Масштаб"); Slider(value: $project.elements[i].scale, in: 0.2...4.0) }
                        HStack { Text("Поворот"); Slider(value: $project.elements[i].rotation, in: -180...180) }
                        HStack { Text("Прозрачность"); Slider(value: $project.elements[i].opacity, in: 0.05...1.0) }
                    }
                    if project.elements[i].kind != .image {
                        Section("Цвет") { TextField("HEX", text: $project.elements[i].fillHex) }
                    }
                    Button("Удалить объект", role: .destructive) {
                        project.elements.remove(at: i); selectedID = nil; dismiss()
                    }
                } else {
                    Text("Выберите объект на холсте").foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Свойства")
            .toolbar { Button("Готово") { dismiss() } }
        }
    }
}
