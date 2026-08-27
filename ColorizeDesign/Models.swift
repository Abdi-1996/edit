import SwiftUI

struct SignProject: Identifiable, Codable {
    var id = UUID()
    var name: String
    var widthCM: Double
    var heightCM: Double
    var type: SignType
    var backgroundHex: String = "#FFFFFF"
    var elements: [CanvasElement] = []
}

enum SignType: String, Codable, CaseIterable, Identifiable {
    case banner = "Баннер"
    case lightbox = "Лайтбокс"
    case channelLetters = "Объёмные буквы"
    case panel = "Композитная панель"
    case window = "Витрина"
    case plate = "Табличка"
    var id: String { rawValue }
}

struct CanvasElement: Identifiable, Codable {
    enum Kind: String, Codable { case text, rectangle, image }
    var id = UUID()
    var kind: Kind
    var text: String = ""
    var imageData: Data? = nil
    var x: Double = 0.5
    var y: Double = 0.5
    var width: Double = 0.35
    var height: Double = 0.18
    var rotation: Double = 0
    var scale: Double = 1
    var opacity: Double = 1
    var fillHex: String = "#111111"
    var fontSize: Double = 42
}

extension Color {
    init(hex: String) {
        let h = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var v: UInt64 = 0
        Scanner(string: h).scanHexInt64(&v)
        let r, g, b: UInt64
        switch h.count {
        case 6: (r,g,b) = (v >> 16, v >> 8 & 0xff, v & 0xff)
        default: (r,g,b) = (255,255,255)
        }
        self.init(.sRGB, red: Double(r)/255, green: Double(g)/255, blue: Double(b)/255, opacity: 1)
    }
}
