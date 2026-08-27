import SwiftUI
import PhotosUI

struct GridOverlay: View {
    let columns: Int
    let rows: Int
    var body: some View {
        GeometryReader { geo in
            Path { path in
                for i in 1..<columns {
                    let x = geo.size.width * CGFloat(i) / CGFloat(columns)
                    path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: geo.size.height))
                }
                for i in 1..<rows {
                    let y = geo.size.height * CGFloat(i) / CGFloat(rows)
                    path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: geo.size.width, y: y))
                }
            }
            .stroke(.secondary.opacity(0.22), lineWidth: 0.7)
        }
        .allowsHitTesting(false)
    }
}

struct FacadeMockupView: View {
    @Environment(\.dismiss) private var dismiss
    let facadeImage: UIImage?
    let project: SignProject
    @State private var scale: CGFloat = 0.62
    @State private var offset: CGSize = .zero
    @State private var rotation: Double = 0

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                if let facadeImage {
                    Image(uiImage: facadeImage).resizable().scaledToFit()
                } else {
                    ContentUnavailableView("Добавьте фото фасада", systemImage: "building.2.crop.circle")
                        .foregroundStyle(.white)
                }
                if facadeImage != nil {
                    signPreview
                        .scaleEffect(scale)
                        .rotationEffect(.degrees(rotation))
                        .offset(offset)
                        .gesture(DragGesture().onChanged { offset = $0.translation })
                        .gesture(MagnificationGesture().onChanged { scale = min(max($0, 0.2), 2.0) })
                        .gesture(RotationGesture().onChanged { rotation = $0.degrees })
                }
            }
            .navigationTitle("Mockup фасада")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Готово") { dismiss() } }
        }
    }

    private var signPreview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5).fill(Color(hex: project.backgroundHex))
            Text(project.elements.first(where: {$0.kind == .text})?.text ?? project.name)
                .font(.system(size: 34, weight: .black))
                .foregroundStyle(.black)
                .padding(18)
        }
        .frame(width: 330, height: max(70, 330 / CGFloat(project.widthCM / max(project.heightCM, 1))))
        .shadow(color: .black.opacity(0.35), radius: 8, y: 4)
    }
}

struct PhotoImportButton: View {
    @Binding var selectedItem: PhotosPickerItem?
    let title: String
    let icon: String
    var body: some View {
        PhotosPicker(selection: $selectedItem, matching: .images) {
            VStack(spacing: 3) { Image(systemName: icon).font(.title3); Text(title).font(.caption2) }
        }
    }
}
