import SwiftUI
import Foundation

enum WorkspaceMode: String, CaseIterable, Identifiable, Codable {
    case design = "Design"
    case mockup = "Mockup"
    case preview3D = "3D"
    case production = "Production"
    case cost = "Cost"
    case export = "Export"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .design: return "pencil.and.ruler.fill"
        case .mockup: return "building.2.crop.circle"
        case .preview3D: return "cube.transparent"
        case .production: return "wrench.and.screwdriver.fill"
        case .cost: return "banknote.fill"
        case .export: return "square.and.arrow.up.fill"
        }
    }
}

enum EditorTool: String, CaseIterable, Identifiable {
    case move = "Move"
    case node = "Node"
    case pen = "Pen"
    case pencil = "Pencil"
    case text = "Text"
    case rectangle = "Rectangle"
    case ellipse = "Ellipse"
    case image = "Image"
    case gradient = "Gradient"
    case transparency = "Transparency"
    case measure = "Measure"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .move: return "arrow.up.left"
        case .node: return "point.topleft.down.to.point.bottomright.curvepath"
        case .pen: return "pencil.tip"
        case .pencil: return "pencil.line"
        case .text: return "textformat"
        case .rectangle: return "rectangle"
        case .ellipse: return "circle"
        case .image: return "photo"
        case .gradient: return "circle.lefthalf.filled"
        case .transparency: return "checkerboard.rectangle"
        case .measure: return "ruler"
        }
    }
}

enum CanvasObjectKind: String, Codable, CaseIterable {
    case text, rectangle, ellipse, image, line
}

struct CanvasObject: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var kind: CanvasObjectKind
    var x: Double = 0.5
    var y: Double = 0.5
    var width: Double = 0.35
    var height: Double = 0.20
    var rotation: Double = 0
    var opacity: Double = 1
    var fillHex: String = "#111111"
    var strokeHex: String = "#000000"
    var strokeWidth: Double = 0
    var cornerRadius: Double = 0
    var text: String = ""
    var fontSize: Double = 52
    var fontWeight: String = "bold"
    var letterSpacing: Double = 0
    var imageData: Data? = nil
    var isHidden: Bool = false
    var isLocked: Bool = false
}

enum SignType: String, Codable, CaseIterable, Identifiable {
    case banner = "Баннер"
    case channelLetters = "Объёмные буквы"
    case lightbox = "Лайтбокс"
    case composite = "Композитная панель"
    case window = "Витрина"
    case plate = "Табличка"
    case pylon = "Пилон"
    var id: String { rawValue }
}

enum MaterialType: String, Codable, CaseIterable, Identifiable {
    case banner = "Баннер 440"
    case acrylic = "Акрил 3 мм"
    case pvc = "ПВХ 5 мм"
    case acp = "АКП 3 мм"
    case aluminum = "Алюминий"
    case vinyl = "Плёнка"
    var id: String { rawValue }
    var defaultPricePerM2: Double {
        switch self {
        case .banner: return 3500
        case .acrylic: return 10500
        case .pvc: return 6500
        case .acp: return 9000
        case .aluminum: return 15000
        case .vinyl: return 4500
        }
    }
}

struct ProductionSettings: Codable, Hashable {
    var material: MaterialType = .acp
    var materialPricePerM2: Double = 9000
    var wastePercent: Double = 12
    var ledEnabled: Bool = false
    var ledModulesPerM2: Double = 38
    var wattsPerModule: Double = 0.72
    var laborCost: Double = 15000
    var installationCost: Double = 12000
    var markupPercent: Double = 35
}

struct SignProject: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var widthCM: Double
    var heightCM: Double
    var signType: SignType
    var backgroundHex: String = "#FFFFFF"
    var objects: [CanvasObject] = []
    var production = ProductionSettings()
    var createdAt = Date()
    var updatedAt = Date()

    var areaM2: Double { max(0.01, widthCM * heightCM / 10_000.0) }
}

extension Color {
    init(hex: String) {
        let raw = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: raw).scanHexInt64(&value)
        let r, g, b: UInt64
        if raw.count == 6 {
            r = value >> 16
            g = (value >> 8) & 0xff
            b = value & 0xff
        } else {
            r = 255; g = 255; b = 255
        }
        self.init(.sRGB, red: Double(r)/255.0, green: Double(g)/255.0, blue: Double(b)/255.0, opacity: 1)
    }
}

extension String {
    static let sampleProjectName = "Новая вывеска"
}
