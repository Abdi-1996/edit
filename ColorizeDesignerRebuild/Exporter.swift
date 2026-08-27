import SwiftUI
import UIKit

struct ExportWorkspace: View {
    let project: SignProject
    @State private var pngURL: URL?
    @State private var pdfURL: URL?
    @State private var scale = 2.0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Export").font(.largeTitle.bold())
                ProjectPreview(project: project)
                    .aspectRatio(project.widthCM / max(project.heightCM, 1), contentMode: .fit)
                    .frame(maxWidth: 760)
                    .background(Color.white.opacity(0.03))
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(.white.opacity(0.15)))
                VStack(alignment: .leading, spacing: 12) {
                    Text("Raster preview quality").font(.headline)
                    Picker("Scale", selection: $scale) {
                        Text("1×").tag(1.0); Text("2×").tag(2.0); Text("4×").tag(4.0)
                    }.pickerStyle(.segmented)
                    HStack {
                        Button { pngURL = ExportEngine.makePNG(project: project, scale: scale) } label: { Label("Create PNG", systemImage: "photo") }.buttonStyle(.borderedProminent)
                        Button { pdfURL = ExportEngine.makePDF(project: project) } label: { Label("Create PDF", systemImage: "doc.richtext") }.buttonStyle(.bordered)
                    }
                    if let pngURL { ShareLink(item: pngURL) { Label("Share PNG", systemImage: "square.and.arrow.up") } }
                    if let pdfURL { ShareLink(item: pdfURL) { Label("Share PDF", systemImage: "square.and.arrow.up") } }
                }
                .padding(16).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
                VStack(alignment: .leading, spacing: 8) {
                    Label("Real dimensions: \(Int(project.widthCM)) × \(Int(project.heightCM)) cm", systemImage: "ruler")
                    Label("PDF preview includes project size and production data", systemImage: "doc.text")
                    Label("SVG/DXF/PDF-X will be added with the vector engine", systemImage: "info.circle")
                }.font(.footnote).foregroundStyle(.secondary)
            }.padding(24)
        }
    }
}

enum ExportEngine {
    @MainActor
    static func makePNG(project: SignProject, scale: Double) -> URL? {
        let ratio = project.widthCM / max(project.heightCM, 1)
        let width = min(3200.0, max(900.0, 1100.0 * scale))
        let height = width / ratio
        let renderer = ImageRenderer(content: ProjectPreview(project: project).frame(width: width, height: height))
        renderer.scale = 1
        guard let image = renderer.uiImage, let data = image.pngData() else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(safe(project.name) + ".png")
        try? data.write(to: url)
        return url
    }

    @MainActor
    static func makePDF(project: SignProject) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(safe(project.name) + ".pdf")
        let page = CGRect(x: 0, y: 0, width: 842, height: 595)
        let renderer = UIGraphicsPDFRenderer(bounds: page)
        do {
            try renderer.writePDF(to: url) { ctx in
                ctx.beginPage()
                let title = "\(project.name)  ·  \(Int(project.widthCM)) × \(Int(project.heightCM)) cm"
                (title as NSString).draw(at: CGPoint(x: 36, y: 28), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 18), .foregroundColor: UIColor.black])
                let previewRenderer = ImageRenderer(content: ProjectPreview(project: project).frame(width: 760, height: 360))
                if let image = previewRenderer.uiImage { image.draw(in: CGRect(x: 40, y: 78, width: 760, height: 360)) }
                let info = "Type: \(project.signType.rawValue)    Area: \(String(format: "%.2f", project.areaM2)) m²    Material: \(project.production.material.rawValue)"
                (info as NSString).draw(at: CGPoint(x: 40, y: 470), withAttributes: [.font: UIFont.systemFont(ofSize: 12), .foregroundColor: UIColor.darkGray])
            }
            return url
        } catch { return nil }
    }

    private static func safe(_ name: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        return name.unicodeScalars.map { allowed.contains($0) ? String($0) : "_" }.joined()
    }
}
