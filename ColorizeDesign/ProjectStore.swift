import Foundation

@MainActor
final class ProjectStore: ObservableObject {
    @Published var projects: [SignProject] = [] { didSet { save() } }
    private let key = "colorize.design.projects.v3"

    init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([SignProject].self, from: data) {
            projects = decoded
        } else {
            projects = [SignProject(name: "Пример вывески", widthCM: 350, heightCM: 80, type: .banner,
                elements: [CanvasElement(name: "COLORIZE", kind: .text, text: "COLORIZE", x: 0.5, y: 0.45, width: 0.62, height: 0.28, fillHex: "#111111", fontSize: 54)])]
        }
    }

    func save() {
        guard let data = try? JSONEncoder().encode(projects) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    func duplicate(_ project: SignProject) {
        var copy = project
        copy.id = UUID()
        copy.name += " копия"
        copy.modifiedAt = Date()
        projects.insert(copy, at: 0)
    }
}
