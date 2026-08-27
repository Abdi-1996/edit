import Foundation
import SwiftUI

@MainActor
final class ProjectStore: ObservableObject {
    @Published var projects: [SignProject] = [] { didSet { save() } }
    private let key = "ColorizeDesignerRebuild.projects.v1"

    init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([SignProject].self, from: data) {
            projects = decoded
        } else {
            projects = [Self.sample]
        }
    }

    func add(_ project: SignProject) { projects.insert(project, at: 0) }
    func delete(at offsets: IndexSet) { projects.remove(atOffsets: offsets) }
    func duplicate(_ project: SignProject) {
        var copy = project
        copy.id = UUID()
        copy.name += " Copy"
        copy.createdAt = Date(); copy.updatedAt = Date()
        projects.insert(copy, at: 0)
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(projects) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    static var sample: SignProject {
        SignProject(
            name: "COLORIZE",
            widthCM: 350,
            heightCM: 80,
            signType: .channelLetters,
            backgroundHex: "#F2F2F0",
            objects: [
                CanvasObject(name: "COLORIZE", kind: .text, x: 0.50, y: 0.43, width: 0.68, height: 0.30, fillHex: "#7119E8", text: "COLORIZE", fontSize: 72, fontWeight: "black"),
                CanvasObject(name: "Подзаголовок", kind: .text, x: 0.50, y: 0.68, width: 0.55, height: 0.16, fillHex: "#202020", text: "DESIGN STUDIO", fontSize: 28, fontWeight: "semibold")
            ]
        )
    }
}
