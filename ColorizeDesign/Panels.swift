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
                            Image(systemName: el.kind == .text ? "textformat" : "square.fill")
                            Text(el.kind == .text ? (el.text.isEmpty ? "Текст" : el.text) : "Фигура")
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
                    Section("Размер и положение") {
                        HStack { Text("Ширина"); Slider(value: $project.elements[i].width, in: 0.05...0.95) }
                        HStack { Text("Высота"); Slider(value: $project.elements[i].height, in: 0.05...0.95) }
                        HStack { Text("Поворот"); Slider(value: $project.elements[i].rotation, in: -180...180) }
                    }
                    Section("Цвет") { TextField("HEX", text: $project.elements[i].fillHex) }
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
