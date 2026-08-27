import SwiftUI
import UIKit

struct ProductionView: View {
    @Binding var project: SignProject
    private var area: Double { (project.widthCM / 100) * (project.heightCM / 100) }
    private var materialArea: Double { area * (1 + project.production.wastePercent / 100) }
    private var materialCost: Double { materialArea * project.production.materialPricePerM2 }
    private var ledCount: Int {
        guard project.production.ledEnabled else { return 0 }
        let spacing = max(project.production.ledSpacingCM, 2)
        return Int(ceil(project.widthCM / spacing) * ceil(project.heightCM / spacing))
    }
    private var ledWatts: Double { Double(ledCount) * project.production.ledModuleWatt }
    private var total: Double { materialCost + project.production.laborPrice + project.production.installationPrice }

    var body: some View {
        NavigationStack {
            Form {
                Section("Конструкция") {
                    Picker("Материал", selection: $project.production.material) {
                        ForEach(MaterialType.allCases) { Text($0.rawValue).tag($0) }
                    }
                    HStack { Text("Толщина"); Spacer(); TextField("3", value: $project.production.thicknessMM, format: .number); Text("мм") }
                    if project.type == .channelLetters || project.type == .lightbox {
                        HStack { Text("Глубина"); Spacer(); TextField("80", value: $project.production.depthMM, format: .number); Text("мм") }
                    }
                }
                Section("Подсветка") {
                    Toggle("LED", isOn: $project.production.ledEnabled)
                    if project.production.ledEnabled {
                        HStack { Text("Шаг модулей"); Spacer(); TextField("10", value: $project.production.ledSpacingCM, format: .number); Text("см") }
                        HStack { Text("Мощность модуля"); Spacer(); TextField("0.72", value: $project.production.ledModuleWatt, format: .number); Text("Вт") }
                        LabeledContent("Примерно модулей", value: "\(ledCount)")
                        LabeledContent("Расчётная мощность", value: String(format: "%.1f Вт", ledWatts))
                        LabeledContent("Рекомендуемый БП", value: "\(Int(ceil(ledWatts * 1.25 / 10) * 10)) Вт")
                    }
                }
                Section("Смета") {
                    HStack { Text("Запас материала"); Spacer(); TextField("12", value: $project.production.wastePercent, format: .number); Text("%") }
                    HStack { Text("Цена за м²"); Spacer(); TextField("0", value: $project.production.materialPricePerM2, format: .number) }
                    HStack { Text("Работа"); Spacer(); TextField("0", value: $project.production.laborPrice, format: .number) }
                    HStack { Text("Монтаж"); Spacer(); TextField("0", value: $project.production.installationPrice, format: .number) }
                    LabeledContent("Площадь", value: String(format: "%.2f м²", area))
                    LabeledContent("С запасом", value: String(format: "%.2f м²", materialArea))
                    LabeledContent("Итого", value: String(format: "%.0f", total))
                }
                Section("Производственная проверка") {
                    checkRow(project.widthCM >= 10 && project.heightCM >= 10, "Размер проекта")
                    checkRow(project.elements.contains(where: { !$0.hidden }), "Есть видимые элементы")
                    checkRow(!project.production.ledEnabled || ledWatts > 0, "LED расчёт")
                }
            }
            .navigationTitle("Production")
        }
    }

    private func checkRow(_ ok: Bool, _ title: String) -> some View {
        HStack { Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"); Text(title); Spacer(); Text(ok ? "OK" : "Проверить").foregroundStyle(.secondary) }
    }
}

struct AIStudioView: View {
    @Binding var project: SignProject
    @State private var prompt = ""
    @State private var status = ""
    var body: some View {
        NavigationStack {
            Form {
                Section("AI Designer") {
                    TextField("Например: сделай название крупнее и по центру", text: $prompt, axis: .vertical)
                    Button("Применить локальную команду") { applySimpleCommand() }
                    if !status.isEmpty { Text(status).font(.footnote).foregroundStyle(.secondary) }
                }
                Section("Локальные AI-инструменты") {
                    Label("Удаление фона — модуль подготовлен", systemImage: "person.crop.rectangle.badge.minus")
                    Label("Vectorize — модуль подготовлен", systemImage: "point.3.connected.trianglepath.dotted")
                    Label("OCR / распознавание текста", systemImage: "text.viewfinder")
                    Label("Upscale / Enhance", systemImage: "wand.and.stars")
                }
                Section("ChatGPT") {
                    Text("Для реального ChatGPT нужен API-ключ OpenAI. В этой сборке интерфейс и точка подключения подготовлены, но ключ не вшит в IPA.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("AI")
        }
    }
    private func applySimpleCommand() {
        let q = prompt.lowercased()
        if q.contains("крупн") || q.contains("увелич") {
            for i in project.elements.indices where project.elements[i].kind == .text { project.elements[i].scale = min(project.elements[i].scale * 1.15, 4) }
            status = "Текст увеличен"
        } else if q.contains("центр") {
            for i in project.elements.indices where project.elements[i].kind == .text { project.elements[i].x = 0.5; project.elements[i].y = 0.5 }
            status = "Текст выровнен по центру"
        } else if q.contains("скры") {
            status = "Выберите слой и используйте скрытие в панели слоёв"
        } else {
            status = "Команда не распознана локально. Для свободных команд подключите ChatGPT API."
        }
    }
}

struct ExportCenterView: View {
    let project: SignProject
    @State private var pngURL: URL?
    @State private var pdfURL: URL?
    var body: some View {
        NavigationStack {
            Form {
                Section("Проверка перед экспортом") {
                    LabeledContent("Размер", value: "\(Int(project.widthCM)) × \(Int(project.heightCM)) см")
                    LabeledContent("Слои", value: "\(project.elements.filter { !$0.hidden }.count)")
                    LabeledContent("Цветовой режим", value: "RGB preview")
                    Text("PDF/PNG в V3 предназначены для превью и согласования. Полный CMYK/PDF-X требует отдельного цветового движка.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Экспорт") {
                    Button("Подготовить PNG") { pngURL = ProjectRenderer.makePNG(project) }
                    if let pngURL { ShareLink(item: pngURL) { Label("Поделиться PNG", systemImage: "square.and.arrow.up") } }
                    Button("Подготовить PDF") { pdfURL = ProjectRenderer.makePDF(project) }
                    if let pdfURL { ShareLink(item: pdfURL) { Label("Поделиться PDF", systemImage: "doc.richtext") } }
                }
            }
            .navigationTitle("Export")
        }
    }
}

enum ProjectRenderer {
    static func image(_ project: SignProject, size: CGSize = CGSize(width: 1600, height: 900)) -> UIImage {
        let ratio = project.widthCM / max(project.heightCM, 1)
        let h = size.width / ratio
        let target = CGSize(width: size.width, height: min(max(h, 300), 1600))
        let renderer = UIGraphicsImageRenderer(size: target)
        return renderer.image { ctx in
            UIColor(Color(hex: project.backgroundHex)).setFill()
            ctx.fill(CGRect(origin: .zero, size: target))
            for e in project.elements where !e.hidden {
                ctx.cgContext.saveGState()
                let cx = e.x * target.width, cy = e.y * target.height
                ctx.cgContext.translateBy(x: cx, y: cy)
                ctx.cgContext.rotate(by: CGFloat(e.rotation * .pi / 180))
                ctx.cgContext.setAlpha(e.opacity)
                let w = e.width * target.width * e.scale, h = e.height * target.height * e.scale
                let rect = CGRect(x: -w/2, y: -h/2, width: w, height: h)
                switch e.kind {
                case .rectangle:
                    UIColor(Color(hex: e.fillHex)).setFill(); UIBezierPath(roundedRect: rect, cornerRadius: 12).fill()
                case .text:
                    let style = NSMutableParagraphStyle(); style.alignment = .center
                    let attrs: [NSAttributedString.Key: Any] = [.font: UIFont.boldSystemFont(ofSize: CGFloat(e.fontSize * 2.2)), .foregroundColor: UIColor(Color(hex: e.fillHex)), .paragraphStyle: style]
                    NSString(string: e.text).draw(in: rect, withAttributes: attrs)
                case .image:
                    if let data = e.imageData, let img = UIImage(data: data) { img.draw(in: rect) }
                }
                ctx.cgContext.restoreGState()
            }
        }
    }
    static func makePNG(_ project: SignProject) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(project.name)-preview.png")
        guard let data = image(project).pngData() else { return nil }
        try? data.write(to: url); return url
    }
    static func makePDF(_ project: SignProject) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(project.name)-preview.pdf")
        let img = image(project)
        let bounds = CGRect(origin: .zero, size: img.size)
        let renderer = UIGraphicsPDFRenderer(bounds: bounds)
        do { try renderer.writePDF(to: url) { c in c.beginPage(); img.draw(in: bounds) }; return url } catch { return nil }
    }
}
