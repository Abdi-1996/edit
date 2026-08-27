import SwiftUI
import UIKit

struct DesignerProject: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var widthMM: Double
    var heightMM: Double
    var backgroundHex: String = "#111111"
    var elements: [DesignElement] = []
    var material: MaterialKind = .acrylic
    var depthMM: Double = 70
    var ledEnabled: Bool = true
    var facadeImageData: Data? = nil
}

enum MaterialKind: String, Codable, CaseIterable, Identifiable {
    case acrylic = "Акрил"
    case pvc = "ПВХ"
    case composite = "Композит"
    case aluminum = "Алюминий"
    case steel = "Нержавейка"
    case banner = "Баннер"
    var id: String { rawValue }
}

struct DesignElement: Identifiable, Codable, Equatable {
    enum Kind: String, Codable { case text, rectangle, ellipse, star, image }
    var id = UUID()
    var kind: Kind
    var name: String
    var text: String = ""
    var imageData: Data? = nil
    var x: Double = 0.5
    var y: Double = 0.5
    var width: Double = 0.35
    var height: Double = 0.18
    var rotation: Double = 0
    var opacity: Double = 1
    var fillHex: String = "#FF0000"
    var strokeHex: String = "#FFFFFF"
    var strokeWidth: Double = 0
    var fontSize: Double = 48
    var locked: Bool = false
    var hidden: Bool = false
}

@MainActor
final class ProjectStore: ObservableObject {
    @Published var projects: [DesignerProject] = [] { didSet { save() } }
    private let key = "colorize_designer_projects_v1"

    init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([DesignerProject].self, from: data) {
            projects = decoded
        } else {
            projects = [Self.demo]
        }
    }

    func addProject() {
        let p = DesignerProject(name: "Новый проект", widthMM: 3500, heightMM: 800,
            elements: [DesignElement(kind: .text, name: "COLORIZE", text: "COLORIZE", x: 0.56, y: 0.45, width: 0.55, height: 0.25, fillHex: "#FF0000", fontSize: 68)])
        projects.insert(p, at: 0)
    }

    func duplicate(_ project: DesignerProject) {
        var p = project; p.id = UUID(); p.name += " копия"; projects.insert(p, at: 0)
    }

    func delete(_ project: DesignerProject) { projects.removeAll { $0.id == project.id } }

    private func save() {
        guard let data = try? JSONEncoder().encode(projects) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    static let demo = DesignerProject(name: "Вывеска COLORIZE", widthMM: 3600, heightMM: 800,
        elements: [
            DesignElement(kind: .text, name: "COLORIZE", text: "COLORIZE", x: 0.55, y: 0.45, width: 0.58, height: 0.28, fillHex: "#FF0000", fontSize: 72),
            DesignElement(kind: .text, name: "DESIGNER", text: "DESIGNER", x: 0.73, y: 0.66, width: 0.30, height: 0.12, fillHex: "#FFFFFF", fontSize: 28)
        ])
}

extension Color {
    init(hex: String) {
        let clean = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: clean).scanHexInt64(&value)
        let r, g, b: UInt64
        if clean.count == 6 { r = value >> 16; g = value >> 8 & 255; b = value & 255 }
        else { r = 255; g = 255; b = 255 }
        self.init(.sRGB, red: Double(r)/255, green: Double(g)/255, blue: Double(b)/255, opacity: 1)
    }
}
