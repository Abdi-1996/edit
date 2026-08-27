import SwiftUI

struct NewProjectView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = String.sampleProjectName
    @State private var width = 350.0
    @State private var height = 80.0
    @State private var signType: SignType = .banner
    @State private var background = "#FFFFFF"
    let onCreate: (SignProject) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Проект") {
                    TextField("Название", text: $name)
                    Picker("Тип вывески", selection: $signType) { ForEach(SignType.allCases) { Text($0.rawValue).tag($0) } }
                }
                Section("Реальный размер") {
                    HStack { Text("Ширина"); Spacer(); TextField("350", value: $width, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing); Text("см").foregroundStyle(.secondary) }
                    HStack { Text("Высота"); Spacer(); TextField("80", value: $height, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing); Text("см").foregroundStyle(.secondary) }
                }
                Section("Фон") { TextField("HEX", text: $background).textInputAutocapitalization(.characters) }
                Section {
                    Label("Холст создаётся в точном соотношении сторон. Размеры сохраняются в реальных единицах.", systemImage: "ruler")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Новый проект")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Создать") {
                        onCreate(SignProject(name: name.isEmpty ? "Без названия" : name, widthCM: max(width, 1), heightCM: max(height, 1), signType: signType, backgroundHex: background))
                        dismiss()
                    }
                }
            }
        }
    }
}
