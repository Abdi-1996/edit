import SwiftUI

struct RootView: View {
    @StateObject private var store = ProjectStore()
    @State private var showingNewProject = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 18) {
                        hero
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 14)], spacing: 14) {
                            ForEach(store.projects) { project in
                                NavigationLink { EditorView(project: binding(for: project), onSave: store.save) } label: { ProjectCard(project: project) }
                                    .buttonStyle(.plain)
                                    .contextMenu {
                                        Button { store.duplicate(project) } label: { Label("Дублировать", systemImage: "plus.square.on.square") }
                                        Button(role: .destructive) { store.projects.removeAll { $0.id == project.id } } label: { Label("Удалить", systemImage: "trash") }
                                    }
                            }
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Colorize Design")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { showingNewProject = true } label: { Image(systemName: "plus") } } }
            .sheet(isPresented: $showingNewProject) {
                NewProjectView { project in store.projects.insert(project, at: 0) }
            }
        }
    }

    private var hero: some View {
        HStack {
            VStack(alignment: .leading, spacing: 7) {
                Text("Colorize Design Full").font(.title2.bold())
                Text("Дизайн · Mockup · AI · Production · Export").foregroundStyle(.secondary)
                Button("Новый проект") { showingNewProject = true }.buttonStyle(.borderedProminent)
            }
            Spacer()
            Image(systemName: "paintpalette.fill").font(.system(size: 54)).symbolRenderingMode(.hierarchical)
        }
        .padding(20)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func binding(for project: SignProject) -> Binding<SignProject> {
        guard let idx = store.projects.firstIndex(where: { $0.id == project.id }) else { return .constant(project) }
        return $store.projects[idx]
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
