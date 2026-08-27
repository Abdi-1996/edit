import SwiftUI

struct NewProjectView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = "Новая вывеска"
    @State private var width = 350.0
    @State private var height = 80.0
    @State private var type: SignType = .banner
    let onCreate: (SignProject) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Проект") {
                    TextField("Название", text: $name)
                    Picker("Тип", selection: $type) {
                        ForEach(SignType.allCases) { Text($0.rawValue).tag($0) }
                    }
                }
                Section("Реальный размер") {
                    HStack { Text("Ширина"); Spacer(); TextField("350", value: $width, format: .number).multilineTextAlignment(.trailing); Text("см") }
                    HStack { Text("Высота"); Spacer(); TextField("80", value: $height, format: .number).multilineTextAlignment(.trailing); Text("см") }
                }
                Section {
                    Text("V1 создаёт холст в реальном соотношении сторон. В следующих версиях сюда добавятся замер фасада, AR и производственные параметры.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Новый проект")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Создать") {
                        onCreate(SignProject(name: name, widthCM: max(width, 1), heightCM: max(height, 1), type: type))
                        dismiss()
                    }
                }
            }
        }
    }
}
