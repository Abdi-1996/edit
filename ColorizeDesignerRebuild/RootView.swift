import SwiftUI

struct RootView: View {
    @EnvironmentObject private var store: ProjectStore
    @State private var showNewProject = false

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(colors: [Color(red: 0.07, green: 0.07, blue: 0.09), Color(red: 0.03, green: 0.03, blue: 0.04)], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        header
                        if store.projects.isEmpty {
                            ContentUnavailableView("Нет проектов", systemImage: "rectangle.on.rectangle.slash", description: Text("Создайте первый макет вывески"))
                                .frame(maxWidth: .infinity, minHeight: 340)
                        } else {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 16)], spacing: 16) {
                                ForEach(store.projects) { project in
                                    NavigationLink {
                                        if let index = store.projects.firstIndex(where: { $0.id == project.id }) {
                                            EditorView(project: $store.projects[index])
                                        }
                                    } label: {
                                        ProjectCard(project: project)
                                    }
                                    .buttonStyle(.plain)
                                    .contextMenu {
                                        Button { store.duplicate(project) } label: { Label("Дублировать", systemImage: "plus.square.on.square") }
                                        Button(role: .destructive) {
                                            if let index = store.projects.firstIndex(where: { $0.id == project.id }) { store.projects.remove(at: index) }
                                        } label: { Label("Удалить", systemImage: "trash") }
                                    }
                                }
                            }
                        }
                    }
                    .padding(20)
                }
            }
            .navigationBarHidden(true)
            .sheet(isPresented: $showNewProject) {
                NewProjectView { store.add($0) }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 16) {
            BrandLogo().frame(width: 48, height: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text("Colorize Designer").font(.title2.weight(.bold))
                Text("Sign & advertising studio").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button { showNewProject = true } label: {
                Label("Новый проект", systemImage: "plus")
                    .font(.headline).padding(.horizontal, 16).padding(.vertical, 11)
                    .background(Color.purple, in: Capsule())
            }
            .buttonStyle(.plain)
        }
    }
}

struct ProjectCard: View {
    let project: SignProject
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 16).fill(Color(hex: project.backgroundHex))
                Text(project.objects.first(where: { $0.kind == .text })?.text ?? project.name)
                    .foregroundStyle(Color(hex: project.objects.first(where: { $0.kind == .text })?.fillHex ?? "#7119E8"))
                    .font(.system(size: 26, weight: .black))
                    .minimumScaleFactor(0.35).lineLimit(1).padding(18)
            }
            .aspectRatio(max(1.6, project.widthCM / max(project.heightCM, 1)), contentMode: .fit)
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.08)))

            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(project.name).font(.headline).foregroundStyle(.white)
                    Text("\(Int(project.widthCM)) × \(Int(project.heightCM)) см · \(project.signType.rawValue)")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(0.07)))
    }
}
