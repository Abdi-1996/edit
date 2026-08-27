import SwiftUI
import PhotosUI

struct EditorView: View {
    @Binding var project: SignProject
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var mode: WorkspaceMode = .design
    @State private var tool: EditorTool = .move
    @State private var selectedID: UUID?
    @State private var showGrid = true
    @State private var showRulers = true
    @State private var snapping = true
    @State private var showInspectorSheet = false
    @State private var imagePickerItem: PhotosPickerItem?
    @State private var undoStack: [SignProject] = []
    @State private var redoStack: [SignProject] = []
    @State private var gestureSnapshot: SignProject?

    private var isCompact: Bool { horizontalSizeClass == .compact }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            workspaceBar
            if mode == .design {
                designWorkspace
            } else {
                WorkspaceHost(mode: mode, project: $project)
            }
        }
        .background(Color(red: 0.045, green: 0.045, blue: 0.055).ignoresSafeArea())
        .navigationTitle(project.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showInspectorSheet) {
            NavigationStack {
                InspectorPanel(project: $project, selectedID: $selectedID, onMutation: recordBeforeMutation)
                    .navigationTitle("Layers & Properties")
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { showInspectorSheet = false } } }
            }
            .presentationDetents([.medium, .large])
        }
        .onChange(of: imagePickerItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    await MainActor.run { addImage(data) }
                }
            }
        }
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            Button(action: undo) { Image(systemName: "arrow.uturn.backward") }.disabled(undoStack.isEmpty)
            Button(action: redo) { Image(systemName: "arrow.uturn.forward") }.disabled(redoStack.isEmpty)
            Divider().frame(height: 20)
            Button { showGrid.toggle() } label: { Image(systemName: showGrid ? "grid" : "square") }
            Button { showRulers.toggle() } label: { Image(systemName: "ruler") }
            Button { snapping.toggle() } label: { Image(systemName: "scope") }.foregroundStyle(snapping ? .purple : .secondary)
            Spacer()
            if let selected = selectedObject {
                Text(selected.name).font(.caption.weight(.semibold)).lineLimit(1).foregroundStyle(.secondary)
            }
            if isCompact {
                Button { showInspectorSheet = true } label: { Image(systemName: "sidebar.right") }
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 14)
        .frame(height: 42)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) { Divider().opacity(0.25) }
    }

    private var workspaceBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 5) {
                ForEach(WorkspaceMode.allCases) { item in
                    Button { mode = item } label: {
                        Label(item.rawValue, systemImage: item.icon)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 11).padding(.vertical, 7)
                            .background(mode == item ? Color.purple.opacity(0.95) : Color.white.opacity(0.05), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 7)
        }
        .background(Color.black.opacity(0.22))
    }

    @ViewBuilder
    private var designWorkspace: some View {
        if isCompact {
            VStack(spacing: 0) {
                CanvasWorkspace(project: $project, selectedID: $selectedID, showGrid: showGrid, showRulers: showRulers, snapping: snapping, onBeginChange: beginContinuousChange, onEndChange: endContinuousChange)
                compactToolBar
            }
        } else {
            HStack(spacing: 0) {
                ToolRail(tool: $tool, imagePickerItem: $imagePickerItem, onAction: handleToolAction)
                    .frame(width: 66)
                Divider().opacity(0.22)
                CanvasWorkspace(project: $project, selectedID: $selectedID, showGrid: showGrid, showRulers: showRulers, snapping: snapping, onBeginChange: beginContinuousChange, onEndChange: endContinuousChange)
                Divider().opacity(0.22)
                InspectorPanel(project: $project, selectedID: $selectedID, onMutation: recordBeforeMutation)
                    .frame(width: 310)
            }
        }
    }

    private var compactToolBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(EditorTool.allCases) { item in
                    if item == .image {
                        PhotosPicker(selection: $imagePickerItem, matching: .images) {
                            ToolChip(item: item, selected: tool == item)
                        }
                    } else {
                        Button { tool = item; handleToolAction(item) } label: { ToolChip(item: item, selected: tool == item) }
                            .buttonStyle(.plain)
                    }
                }
            }.padding(.horizontal, 12).padding(.vertical, 9)
        }
        .background(.ultraThinMaterial)
    }

    private var selectedObject: CanvasObject? {
        guard let id = selectedID else { return nil }
        return project.objects.first(where: { $0.id == id })
    }

    private func handleToolAction(_ item: EditorTool) {
        tool = item
        switch item {
        case .text: addText()
        case .rectangle: addShape(.rectangle)
        case .ellipse: addShape(.ellipse)
        default: break
        }
    }

    private func addText() {
        recordBeforeMutation()
        let object = CanvasObject(name: "Текст", kind: .text, x: 0.5, y: 0.5, width: 0.5, height: 0.18, fillHex: "#7119E8", text: "Новый текст", fontSize: 54, fontWeight: "bold")
        project.objects.append(object); selectedID = object.id
    }

    private func addShape(_ kind: CanvasObjectKind) {
        recordBeforeMutation()
        let object = CanvasObject(name: kind == .ellipse ? "Эллипс" : "Прямоугольник", kind: kind, x: 0.5, y: 0.5, width: 0.32, height: 0.3, fillHex: "#7119E8", strokeHex: "#FFFFFF", strokeWidth: 0)
        project.objects.append(object); selectedID = object.id
    }

    private func addImage(_ data: Data) {
        recordBeforeMutation()
        let object = CanvasObject(name: "Изображение", kind: .image, x: 0.5, y: 0.5, width: 0.46, height: 0.46, imageData: data)
        project.objects.append(object); selectedID = object.id
    }

    private func recordBeforeMutation() {
        undoStack.append(project)
        if undoStack.count > 40 { undoStack.removeFirst() }
        redoStack.removeAll()
        project.updatedAt = Date()
    }

    private func beginContinuousChange() {
        if gestureSnapshot == nil { gestureSnapshot = project }
    }

    private func endContinuousChange() {
        guard let snapshot = gestureSnapshot else { return }
        gestureSnapshot = nil
        if snapshot != project {
            undoStack.append(snapshot)
            if undoStack.count > 40 { undoStack.removeFirst() }
            redoStack.removeAll()
            project.updatedAt = Date()
        }
    }

    private func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(project)
        project = previous
        selectedID = nil
    }

    private func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(project)
        project = next
        selectedID = nil
    }
}

struct ToolChip: View {
    let item: EditorTool
    let selected: Bool
    var body: some View {
        VStack(spacing: 3) {
            Image(systemName: item.icon).font(.system(size: 16, weight: .semibold))
            Text(item.rawValue).font(.system(size: 9, weight: .medium))
        }
        .frame(width: 54, height: 44)
        .background(selected ? Color.purple.opacity(0.85) : Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct ToolRail: View {
    @Binding var tool: EditorTool
    @Binding var imagePickerItem: PhotosPickerItem?
    let onAction: (EditorTool) -> Void
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 6) {
                ForEach(EditorTool.allCases) { item in
                    if item == .image {
                        PhotosPicker(selection: $imagePickerItem, matching: .images) { railButton(item) }
                    } else {
                        Button { tool = item; onAction(item) } label: { railButton(item) }.buttonStyle(.plain)
                    }
                }
            }.padding(.vertical, 10)
        }
        .background(Color.black.opacity(0.32))
    }

    private func railButton(_ item: EditorTool) -> some View {
        Image(systemName: item.icon)
            .font(.system(size: 18, weight: .medium))
            .frame(width: 44, height: 42)
            .background(tool == item ? Color.purple.opacity(0.9) : Color.clear, in: RoundedRectangle(cornerRadius: 10))
            .contentShape(Rectangle())
    }
}
