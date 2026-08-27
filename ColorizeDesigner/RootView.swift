import SwiftUI

struct RootView: View {
    @EnvironmentObject var store: ProjectStore
    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 20) {
                        HStack(spacing: 14) {
                            Image(systemName: "c.circle.fill").font(.system(size: 44)).foregroundStyle(.red)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("COLORIZE").font(.title.bold()).foregroundStyle(.red)
                                Text("DESIGNER").font(.caption.bold()).tracking(3)
                            }
                            Spacer()
                            Button { store.addProject() } label: { Label("Новый проект", systemImage: "plus") }
                                .buttonStyle(.borderedProminent).tint(.red)
                        }
                        .padding(.top, 8)

                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 16)], spacing: 16) {
                            ForEach(store.projects) { project in
                                NavigationLink { EditorView(project: binding(for: project)) } label: {
                                    ProjectCard(project: project)
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button("Дублировать", systemImage: "plus.square.on.square") { store.duplicate(project) }
                                    Button("Удалить", systemImage: "trash", role: .destructive) { store.delete(project) }
                                }
                            }
                        }
                    }
                    .padding()
                }
            }
            .navigationBarHidden(true)
        }
    }

    private func binding(for project: DesignerProject) -> Binding<DesignerProject> {
        guard let i = store.projects.firstIndex(where: { $0.id == project.id }) else { return .constant(project) }
        return $store.projects[i]
    }
}

struct ProjectCard: View {
    let project: DesignerProject
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 18).fill(Color(hex: project.backgroundHex))
                VStack(spacing: 0) {
                    Text(project.elements.first(where: {$0.kind == .text})?.text ?? project.name)
                        .font(.system(size: 34, weight: .black)).foregroundStyle(.red)
                    if let second = project.elements.filter({$0.kind == .text}).dropFirst().first {
                        Text(second.text).font(.caption.bold()).tracking(3)
                    }
                }
            }
            .aspectRatio(max(project.widthMM / max(project.heightMM, 1), 1.7), contentMode: .fit)
            Text(project.name).font(.headline)
            Text("\(Int(project.widthMM)) × \(Int(project.heightMM)) мм")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(14)
        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color.white.opacity(0.08)))
    }
}
