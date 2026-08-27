import SwiftUI

struct RootView: View {
    @State private var projects: [SignProject] = [
        SignProject(name: "Пример вывески", widthCM: 350, heightCM: 80, type: .banner,
                    elements: [CanvasElement(kind: .text, text: "COLORIZE", x: 0.5, y: 0.45, width: 0.62, height: 0.28, fillHex: "#111111", fontSize: 54)])
    ]
    @State private var showingNewProject = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 18) {
                        hero
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 14)], spacing: 14) {
                            ForEach(projects) { project in
                                NavigationLink { EditorView(project: binding(for: project)) } label: { ProjectCard(project: project) }
                                    .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Colorize Design")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button { showingNewProject = true } label: { Image(systemName: "plus") } }
            }
            .sheet(isPresented: $showingNewProject) {
                NewProjectView { project in projects.insert(project, at: 0) }
            }
        }
    }

    private var hero: some View {
        HStack {
            VStack(alignment: .leading, spacing: 7) {
                Text("Дизайн вывесок").font(.title2.bold())
                Text("От реального размера до готового макета").foregroundStyle(.secondary)
                Button("Новый проект") { showingNewProject = true }.buttonStyle(.borderedProminent)
            }
            Spacer()
            Image(systemName: "rectangle.3.group.bubble.left.fill").font(.system(size: 54)).symbolRenderingMode(.hierarchical)
        }
        .padding(20)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func binding(for project: SignProject) -> Binding<SignProject> {
        guard let idx = projects.firstIndex(where: { $0.id == project.id }) else { return .constant(project) }
        return $projects[idx]
    }
}

struct ProjectCard: View {
    let project: SignProject
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(hex: project.backgroundHex))
                .aspectRatio(max(project.widthCM / max(project.heightCM, 1), 1.2), contentMode: .fit)
                .overlay {
                    Text(project.elements.first(where: {$0.kind == .text})?.text ?? project.name)
                        .font(.headline).foregroundStyle(.primary).lineLimit(1).padding()
                }
            Text(project.name).font(.headline)
            Text("\(Int(project.widthCM)) × \(Int(project.heightCM)) см · \(project.type.rawValue)")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(12)
        .background(.background, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}
