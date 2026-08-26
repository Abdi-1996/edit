import SwiftUI
import AVKit
import AVFoundation
import UniformTypeIdentifiers
import UIKit
import CoreImage

enum EditorFilter: String, CaseIterable, Identifiable {
    case original = "Оригинал", vivid = "Яркий", mono = "Ч/Б", cinematic = "Кино", warm = "Тёплый", cool = "Холодный"
    var id: String { rawValue }
    var systemImage: String {
        switch self {
        case .original: return "circle.lefthalf.filled"
        case .vivid: return "sun.max.fill"
        case .mono: return "circle.righthalf.filled"
        case .cinematic: return "film.fill"
        case .warm: return "thermometer.sun.fill"
        case .cool: return "snowflake"
        }
    }
}

enum ExportQuality: String, CaseIterable, Identifiable {
    case hd = "720p", fullHD = "1080p", ultraHD = "4K"
    var id: String { rawValue }
    var presetName: String {
        switch self {
        case .hd: return AVAssetExportPreset1280x720
        case .fullHD: return AVAssetExportPreset1920x1080
        case .ultraHD: return AVAssetExportPreset3840x2160
        }
    }
}

enum InspectorTool: String, Identifiable {
    case trim, speed, audio, text, filters, adjust, enhance, export
    var id: String { rawValue }
}

struct EditorClip: Identifiable, Equatable {
    let id: UUID
    let url: URL
    var name: String
    var duration: Double
    var trimStart: Double
    var trimEnd: Double
    var speed: Double
    var volume: Double

    init(id: UUID = UUID(), url: URL, name: String, duration: Double, trimStart: Double, trimEnd: Double, speed: Double = 1, volume: Double = 1) {
        self.id = id; self.url = url; self.name = name; self.duration = duration
        self.trimStart = trimStart; self.trimEnd = trimEnd; self.speed = speed; self.volume = volume
    }
    var sourceDuration: Double { max(0.05, trimEnd - trimStart) }
    var outputDuration: Double { sourceDuration / max(0.1, speed) }
}

private struct ProjectSnapshot {
    var clips: [EditorClip]
    var selectedClipID: UUID?
    var overlayText: String
    var overlayTextSize: Double
    var overlayTextY: Double
    var selectedFilter: EditorFilter
    var brightness: Double
    var contrast: Double
    var saturation: Double
    var enhanceAmount: Double
}

@MainActor
final class EditorViewModel: ObservableObject {
    @Published var clips: [EditorClip] = []
    @Published var selectedClipID: UUID?
    @Published var player = AVPlayer()
    @Published var currentTime: Double = 0
    @Published var isPlaying = false
    @Published var isImporting = false
    @Published var isAudioImporting = false
    @Published var isExporting = false
    @Published var exportProgress: Double = 0
    @Published var exportedURL: URL?
    @Published var errorMessage: String?
    @Published var selectedFilter: EditorFilter = .original
    @Published var brightness: Double = 0
    @Published var contrast: Double = 1
    @Published var saturation: Double = 1
    @Published var enhanceAmount: Double = 0
    @Published var overlayText: String = ""
    @Published var overlayTextSize: Double = 36
    @Published var overlayTextY: Double = 0.82
    @Published var musicURL: URL?
    @Published var musicName: String?
    @Published var musicVolume: Double = 0.8
    @Published var exportQuality: ExportQuality = .fullHD
    @Published var timelineZoom: Double = 1

    private var timeObserver: Any?
    private var undoStack: [ProjectSnapshot] = []
    private var redoStack: [ProjectSnapshot] = []
    private var progressTimer: Timer?

    init() {
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.05, preferredTimescale: 600), queue: .main) { [weak self] time in
            guard let self else { return }
            Task { @MainActor in
                self.currentTime = max(0, CMTimeGetSeconds(time))
                self.isPlaying = self.player.rate != 0
                self.enforceTrimBoundary()
            }
        }
    }

    var selectedClip: EditorClip? { clips.first(where: { $0.id == selectedClipID }) }
    var selectedIndex: Int? {
        guard let selectedClipID else { return nil }
        return clips.firstIndex(where: { $0.id == selectedClipID })
    }
    var projectDuration: Double { clips.reduce(0) { $0 + $1.outputDuration } }
    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    func importVideos(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        Task {
            var imported: [EditorClip] = []
            for url in urls {
                do {
                    let asset = AVURLAsset(url: url)
                    let time = try await asset.load(.duration)
                    let duration = max(0.1, CMTimeGetSeconds(time))
                    imported.append(EditorClip(url: url, name: url.deletingPathExtension().lastPathComponent, duration: duration, trimStart: 0, trimEnd: duration))
                } catch { errorMessage = "Не удалось открыть \(url.lastPathComponent): \(error.localizedDescription)" }
            }
            guard !imported.isEmpty else { return }
            registerUndo(); clips.append(contentsOf: imported)
            if selectedClipID == nil { selectedClipID = imported.first?.id }
            refreshPreview(resetToTrimStart: true)
        }
    }

    func importMusic(_ url: URL) { musicURL = url; musicName = url.deletingPathExtension().lastPathComponent }
    func selectClip(_ id: UUID) { selectedClipID = id; refreshPreview(resetToTrimStart: true) }

    func playPause() {
        guard let clip = selectedClip else { return }
        if player.rate == 0 {
            if currentTime < clip.trimStart || currentTime >= clip.trimEnd - 0.03 { player.seek(to: CMTime(seconds: clip.trimStart, preferredTimescale: 600)) }
            player.play()
        } else { player.pause() }
    }

    func seek(by delta: Double) {
        guard let clip = selectedClip else { return }
        player.seek(to: CMTime(seconds: min(max(clip.trimStart, currentTime + delta), clip.trimEnd), preferredTimescale: 600))
    }

    private func enforceTrimBoundary() {
        guard let clip = selectedClip, player.rate != 0 else { return }
        if currentTime >= clip.trimEnd { player.pause(); player.seek(to: CMTime(seconds: clip.trimStart, preferredTimescale: 600)) }
    }

    func refreshPreview(resetToTrimStart: Bool = false) {
        guard let clip = selectedClip else { player.replaceCurrentItem(with: nil); return }
        let oldTime = currentTime
        let asset = AVURLAsset(url: clip.url)
        let item = AVPlayerItem(asset: asset)
        item.videoComposition = makeFilterComposition(for: asset)
        player.replaceCurrentItem(with: item)
        let target = resetToTrimStart ? clip.trimStart : min(max(clip.trimStart, oldTime), clip.trimEnd)
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600))
    }

    func setTrimStart(_ value: Double) {
        mutateSelectedClip { $0.trimStart = min(max(0, value), max(0, $0.trimEnd - 0.05)) }
        if let clip = selectedClip { player.seek(to: CMTime(seconds: clip.trimStart, preferredTimescale: 600)) }
    }
    func setTrimEnd(_ value: Double) {
        mutateSelectedClip { $0.trimEnd = max(min($0.duration, value), min($0.duration, $0.trimStart + 0.05)) }
        if let clip = selectedClip { player.seek(to: CMTime(seconds: clip.trimEnd, preferredTimescale: 600)) }
    }
    func setSpeed(_ value: Double) { registerUndo(); mutateSelectedClip(register: false) { $0.speed = min(max(value, 0.1), 5) } }
    func setVolume(_ value: Double) { mutateSelectedClip { $0.volume = min(max(value, 0), 2) } }

    func splitSelectedClip() {
        guard let index = selectedIndex else { return }
        let clip = clips[index]
        let splitTime = min(max(currentTime, clip.trimStart), clip.trimEnd)
        guard splitTime > clip.trimStart + 0.08, splitTime < clip.trimEnd - 0.08 else { errorMessage = "Поставьте курсор внутри клипа, а затем нажмите Split."; return }
        registerUndo()
        var left = clip; left.trimEnd = splitTime
        let right = EditorClip(url: clip.url, name: clip.name, duration: clip.duration, trimStart: splitTime, trimEnd: clip.trimEnd, speed: clip.speed, volume: clip.volume)
        clips[index] = left; clips.insert(right, at: index + 1); selectedClipID = right.id
        refreshPreview(resetToTrimStart: true); haptic(.medium)
    }

    func duplicateSelectedClip() {
        guard let index = selectedIndex else { return }
        let clip = clips[index]; registerUndo()
        let copy = EditorClip(url: clip.url, name: clip.name + " copy", duration: clip.duration, trimStart: clip.trimStart, trimEnd: clip.trimEnd, speed: clip.speed, volume: clip.volume)
        clips.insert(copy, at: index + 1); selectedClipID = copy.id; refreshPreview(resetToTrimStart: true); haptic(.light)
    }

    func deleteSelectedClip() {
        guard let index = selectedIndex else { return }
        registerUndo(); clips.remove(at: index); selectedClipID = clips.isEmpty ? nil : clips[min(index, clips.count - 1)].id
        refreshPreview(resetToTrimStart: true); haptic(.rigid)
    }

    func moveSelectedClip(_ offset: Int) {
        guard let index = selectedIndex else { return }
        let destination = index + offset
        guard clips.indices.contains(destination) else { return }
        registerUndo(); clips.swapAt(index, destination); haptic(.selection)
    }

    private func mutateSelectedClip(register: Bool = true, _ change: (inout EditorClip) -> Void) {
        guard let index = selectedIndex else { return }
        if register { registerUndo() }
        change(&clips[index])
    }

    func setFilter(_ filter: EditorFilter) { registerUndo(); selectedFilter = filter; refreshPreview() }
    func updateColor(brightness: Double? = nil, contrast: Double? = nil, saturation: Double? = nil) {
        if let brightness { self.brightness = brightness }; if let contrast { self.contrast = contrast }; if let saturation { self.saturation = saturation }; refreshPreview()
    }
    func resetColor() { registerUndo(); brightness = 0; contrast = 1; saturation = 1; enhanceAmount = 0; refreshPreview() }
    func setEnhance(_ value: Double) { enhanceAmount = value; refreshPreview() }

    func registerUndo() {
        undoStack.append(snapshot()); if undoStack.count > 40 { undoStack.removeFirst() }; redoStack.removeAll(); objectWillChange.send()
    }
    func undo() { guard let previous = undoStack.popLast() else { return }; redoStack.append(snapshot()); restore(previous); haptic(.selection) }
    func redo() { guard let next = redoStack.popLast() else { return }; undoStack.append(snapshot()); restore(next); haptic(.selection) }
    private func snapshot() -> ProjectSnapshot {
        ProjectSnapshot(clips: clips, selectedClipID: selectedClipID, overlayText: overlayText, overlayTextSize: overlayTextSize, overlayTextY: overlayTextY, selectedFilter: selectedFilter, brightness: brightness, contrast: contrast, saturation: saturation, enhanceAmount: enhanceAmount)
    }
    private func restore(_ snapshot: ProjectSnapshot) {
        clips = snapshot.clips; selectedClipID = snapshot.selectedClipID; overlayText = snapshot.overlayText; overlayTextSize = snapshot.overlayTextSize; overlayTextY = snapshot.overlayTextY
        selectedFilter = snapshot.selectedFilter; brightness = snapshot.brightness; contrast = snapshot.contrast; saturation = snapshot.saturation; enhanceAmount = snapshot.enhanceAmount
        refreshPreview(); objectWillChange.send()
    }

    private func makeFilterComposition(for asset: AVAsset) -> AVVideoComposition? {
        let needed = selectedFilter != .original || abs(brightness) > 0.001 || abs(contrast - 1) > 0.001 || abs(saturation - 1) > 0.001 || enhanceAmount > 0.001
        guard needed else { return nil }
        return AVVideoComposition(asset: asset) { [selectedFilter, brightness, contrast, saturation, enhanceAmount] request in
            request.finish(with: Self.applyLook(to: request.sourceImage, filter: selectedFilter, brightness: brightness, contrast: contrast, saturation: saturation, enhanceAmount: enhanceAmount), context: nil)
        }
    }

    nonisolated private static func applyLook(to source: CIImage, filter: EditorFilter, brightness: Double, contrast: Double, saturation: Double, enhanceAmount: Double) -> CIImage {
        let extent = source.extent
        var image = source.clampedToExtent()
        switch filter {
        case .original: break
        case .vivid:
            image = image.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 1.28, kCIInputContrastKey: 1.08])
            image = image.applyingFilter("CIVibrance", parameters: ["inputAmount": 0.35])
        case .mono: image = image.applyingFilter("CIPhotoEffectNoir")
        case .cinematic:
            image = image.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0.82, kCIInputContrastKey: 1.16])
            image = image.applyingFilter("CITemperatureAndTint", parameters: ["inputNeutral": CIVector(x: 6500, y: 0), "inputTargetNeutral": CIVector(x: 5800, y: 0)])
        case .warm: image = image.applyingFilter("CITemperatureAndTint", parameters: ["inputNeutral": CIVector(x: 6500, y: 0), "inputTargetNeutral": CIVector(x: 5000, y: 0)])
        case .cool: image = image.applyingFilter("CITemperatureAndTint", parameters: ["inputNeutral": CIVector(x: 6500, y: 0), "inputTargetNeutral": CIVector(x: 8000, y: 0)])
        }
        image = image.applyingFilter("CIColorControls", parameters: [kCIInputBrightnessKey: brightness, kCIInputContrastKey: contrast, kCIInputSaturationKey: saturation])
        if enhanceAmount > 0.001 {
            image = image.applyingFilter("CINoiseReduction", parameters: ["inputNoiseLevel": min(0.07, 0.015 + enhanceAmount * 0.045), "inputSharpness": 0.4 + enhanceAmount * 0.4])
            image = image.applyingFilter("CISharpenLuminance", parameters: [kCIInputSharpnessKey: enhanceAmount * 0.75])
            image = image.applyingFilter("CIVibrance", parameters: ["inputAmount": enhanceAmount * 0.18])
        }
        return image.cropped(to: extent)
    }

    nonisolated private static func applyTextOverlay(to base: CIImage, text: String, fontSize: Double, verticalPosition: Double) -> CIImage {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let generator = CIFilter(name: "CITextImageGenerator") else { return base }
        let scaledFont = fontSize * max(1, base.extent.width / 1080)
        generator.setValue(text, forKey: "inputText")
        generator.setValue("HelveticaNeue-Bold", forKey: "inputFontName")
        generator.setValue(scaledFont, forKey: "inputFontSize")
        generator.setValue(1.0, forKey: "inputScaleFactor")
        guard var textImage = generator.outputImage else { return base }
        let maxWidth = base.extent.width * 0.88
        if textImage.extent.width > maxWidth {
            let scale = maxWidth / textImage.extent.width
            textImage = textImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        }
        let x = base.extent.midX - textImage.extent.width / 2 - textImage.extent.minX
        let desiredY = max(0, min(base.extent.height - textImage.extent.height, base.extent.height * CGFloat(1 - verticalPosition) - textImage.extent.height / 2))
        let translated = textImage.transformed(by: CGAffineTransform(translationX: x, y: desiredY - textImage.extent.minY))
        return translated.composited(over: base)
    }

    func exportProject() {
        guard !clips.isEmpty else { return }
        player.pause(); isExporting = true; exportProgress = 0; exportedURL = nil
        Task {
            do { exportedURL = try await makeExport(); exportProgress = 1; haptic(.success) }
            catch { errorMessage = error.localizedDescription; haptic(.error) }
            progressTimer?.invalidate(); progressTimer = nil; isExporting = false
        }
    }

    private func makeExport() async throws -> URL {
        let composition = AVMutableComposition()
        guard let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw NSError(domain: "VeloCut", code: 10, userInfo: [NSLocalizedDescriptionKey: "Не удалось создать видеодорожку"])
        }
        let audioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        var cursor = CMTime.zero
        var firstTransform: CGAffineTransform?
        let audioParams = audioTrack.map { AVMutableAudioMixInputParameters(track: $0) }

        for clip in clips {
            let asset = AVURLAsset(url: clip.url)
            guard let sourceVideo = try await asset.loadTracks(withMediaType: .video).first else { continue }
            if firstTransform == nil { firstTransform = try await sourceVideo.load(.preferredTransform) }
            let sourceDuration = max(0.05, clip.trimEnd - clip.trimStart)
            let sourceRange = CMTimeRange(start: CMTime(seconds: clip.trimStart, preferredTimescale: 600), duration: CMTime(seconds: sourceDuration, preferredTimescale: 600))
            try videoTrack.insertTimeRange(sourceRange, of: sourceVideo, at: cursor)
            if let sourceAudio = try await asset.loadTracks(withMediaType: .audio).first, let audioTrack { try? audioTrack.insertTimeRange(sourceRange, of: sourceAudio, at: cursor) }
            let insertedRange = CMTimeRange(start: cursor, duration: CMTime(seconds: sourceDuration, preferredTimescale: 600))
            let scaledDuration = CMTime(seconds: clip.outputDuration, preferredTimescale: 600)
            videoTrack.scaleTimeRange(insertedRange, toDuration: scaledDuration)
            if let audioTrack { audioTrack.scaleTimeRange(insertedRange, toDuration: scaledDuration) }
            audioParams?.setVolume(Float(clip.volume), at: cursor)
            cursor = cursor + scaledDuration
        }
        if let firstTransform { videoTrack.preferredTransform = firstTransform }

        var musicParams: AVMutableAudioMixInputParameters?
        if let musicURL, let musicTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
            let musicAsset = AVURLAsset(url: musicURL)
            if let sourceMusic = try await musicAsset.loadTracks(withMediaType: .audio).first {
                let musicDuration = try await musicAsset.load(.duration)
                let available = min(CMTimeGetSeconds(musicDuration), CMTimeGetSeconds(cursor))
                if available > 0.05 {
                    let range = CMTimeRange(start: .zero, duration: CMTime(seconds: available, preferredTimescale: 600))
                    try? musicTrack.insertTimeRange(range, of: sourceMusic, at: .zero)
                    let params = AVMutableAudioMixInputParameters(track: musicTrack); params.setVolume(Float(musicVolume), at: .zero); musicParams = params
                }
            }
        }
        let audioMix = AVMutableAudioMix(); audioMix.inputParameters = [audioParams, musicParams].compactMap { $0 }

        let text = overlayText; let textSize = overlayTextSize; let textY = overlayTextY
        let needsVC = selectedFilter != .original || abs(brightness) > 0.001 || abs(contrast - 1) > 0.001 || abs(saturation - 1) > 0.001 || enhanceAmount > 0.001 || !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        var videoComposition: AVVideoComposition?
        if needsVC {
            videoComposition = AVVideoComposition(asset: composition) { [selectedFilter, brightness, contrast, saturation, enhanceAmount, text, textSize, textY] request in
                var image = Self.applyLook(to: request.sourceImage, filter: selectedFilter, brightness: brightness, contrast: contrast, saturation: saturation, enhanceAmount: enhanceAmount)
                image = Self.applyTextOverlay(to: image, text: text, fontSize: textSize, verticalPosition: textY)
                request.finish(with: image, context: nil)
            }
        }

        let output = FileManager.default.temporaryDirectory.appendingPathComponent("VeloCut-\(UUID().uuidString).mp4")
        let compatible = AVAssetExportSession.exportPresets(compatibleWith: composition)
        let preset = compatible.contains(exportQuality.presetName) ? exportQuality.presetName : AVAssetExportPresetHighestQuality
        guard let session = AVAssetExportSession(asset: composition, presetName: preset) else { throw NSError(domain: "VeloCut", code: 11, userInfo: [NSLocalizedDescriptionKey: "Не удалось создать экспорт"]) }
        session.outputURL = output; session.outputFileType = .mp4; session.shouldOptimizeForNetworkUse = true; session.audioMix = audioMix; session.videoComposition = videoComposition
        progressTimer?.invalidate()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self, weak session] _ in
            guard let self, let session else { return }
            Task { @MainActor in self.exportProgress = Double(session.progress) }
        }
        await withCheckedContinuation { continuation in session.exportAsynchronously { continuation.resume() } }
        guard session.status == .completed else { throw session.error ?? NSError(domain: "VeloCut", code: 12, userInfo: [NSLocalizedDescriptionKey: "Ошибка экспорта"]) }
        return output
    }

    enum HapticKind { case light, medium, rigid, selection, success, error }
    func haptic(_ kind: HapticKind) {
        switch kind {
        case .light: UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case .medium: UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        case .rigid: UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        case .selection: UISelectionFeedbackGenerator().selectionChanged()
        case .success: UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .error: UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }
}

struct PlayerView: UIViewControllerRepresentable {
    let player: AVPlayer
    func makeUIViewController(context: Context) -> AVPlayerViewController { let c = AVPlayerViewController(); c.player = player; c.showsPlaybackControls = false; c.videoGravity = .resizeAspect; return c }
    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) { uiViewController.player = player }
}

struct VideoPicker: UIViewControllerRepresentable {
    let onPick: ([URL]) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(onPick) }
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let c = UIDocumentPickerViewController(forOpeningContentTypes: [.movie, .mpeg4Movie, .quickTimeMovie], asCopy: true); c.allowsMultipleSelection = true; c.delegate = context.coordinator; return c
    }
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    final class Coordinator: NSObject, UIDocumentPickerDelegate { let onPick: ([URL]) -> Void; init(_ onPick: @escaping ([URL]) -> Void) { self.onPick = onPick }; func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) { onPick(urls) } }
}

struct AudioPicker: UIViewControllerRepresentable {
    let onPick: (URL) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(onPick) }
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController { let c = UIDocumentPickerViewController(forOpeningContentTypes: [.audio], asCopy: true); c.delegate = context.coordinator; return c }
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    final class Coordinator: NSObject, UIDocumentPickerDelegate { let onPick: (URL) -> Void; init(_ onPick: @escaping (URL) -> Void) { self.onPick = onPick }; func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) { if let url = urls.first { onPick(url) } } }
}

struct ShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: [url], applicationActivities: nil) }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

struct EditorView: View {
    @StateObject private var model = EditorViewModel()
    @State private var inspector: InspectorTool?
    @State private var showShare = false
    @State private var showProjectInfo = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color(uiColor: .systemBackground).ignoresSafeArea()
                VStack(spacing: 0) { topBar; previewArea; playbackBar; timelineArea; bottomToolBar }
            }
            .navigationBarHidden(true)
            .sheet(isPresented: $model.isImporting) { VideoPicker { urls in model.isImporting = false; model.importVideos(urls) } }
            .sheet(isPresented: $model.isAudioImporting) { AudioPicker { url in model.isAudioImporting = false; model.importMusic(url) } }
            .sheet(item: $inspector) { tool in InspectorSheet(tool: tool, model: model).presentationDetents([.height(300), .medium, .large]).presentationDragIndicator(.visible).presentationBackground(.ultraThinMaterial) }
            .sheet(isPresented: $showShare) { if let url = model.exportedURL { ShareSheet(url: url) } }
            .sheet(isPresented: $showProjectInfo) { ProjectInfoSheet(model: model).presentationDetents([.medium]).presentationDragIndicator(.visible) }
            .onChange(of: model.exportedURL) { _, value in if value != nil { showShare = true } }
            .alert("VeloCut", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) { Button("OK", role: .cancel) { model.errorMessage = nil } } message: { Text(model.errorMessage ?? "") }
            .overlay { if model.isExporting { exportOverlay } }
        }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Button { showProjectInfo = true } label: { Image(systemName: "chevron.down").font(.headline.weight(.semibold)).frame(width: 38, height: 38).background(.thinMaterial, in: Circle()) }
            VStack(alignment: .leading, spacing: 1) { Text("VeloCut").font(.headline.weight(.semibold)); Text(model.clips.isEmpty ? "Новый проект" : "\(model.clips.count) клип. • \(format(model.projectDuration))").font(.caption2).foregroundStyle(.secondary) }
            Spacer()
            Button { model.undo() } label: { Image(systemName: "arrow.uturn.backward").frame(width: 34, height: 34) }.disabled(!model.canUndo)
            Button { model.redo() } label: { Image(systemName: "arrow.uturn.forward").frame(width: 34, height: 34) }.disabled(!model.canRedo)
            Button { inspector = .export } label: { Text("Экспорт").font(.subheadline.weight(.semibold)).padding(.horizontal, 14).frame(height: 36).background(Color.accentColor, in: Capsule()).foregroundStyle(.white) }.disabled(model.clips.isEmpty)
        }.padding(.horizontal, 14).padding(.vertical, 8)
    }

    private var previewArea: some View {
        GeometryReader { geometry in
            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color.black)
                if model.selectedClip != nil {
                    PlayerView(player: model.player).clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    if !model.overlayText.isEmpty { Text(model.overlayText).font(.system(size: model.overlayTextSize, weight: .bold, design: .rounded)).multilineTextAlignment(.center).foregroundStyle(.white).shadow(color: .black.opacity(0.9), radius: 4, y: 2).padding(.horizontal, 24).position(x: geometry.size.width / 2, y: geometry.size.height * model.overlayTextY) }
                } else {
                    Button { model.isImporting = true } label: { VStack(spacing: 12) { Image(systemName: "plus.rectangle.on.rectangle").font(.system(size: 40, weight: .medium)); Text("Добавить видео").font(.headline); Text("Можно выбрать несколько MP4 или MOV").font(.caption).foregroundStyle(.secondary) }.foregroundStyle(.white) }.buttonStyle(.plain)
                }
            }.overlay(alignment: .topTrailing) {
                if model.selectedFilter != .original || model.enhanceAmount > 0 { HStack(spacing: 5) { Image(systemName: "wand.and.stars"); Text(model.selectedFilter.rawValue) }.font(.caption2.weight(.semibold)).padding(.horizontal, 9).padding(.vertical, 6).background(.ultraThinMaterial, in: Capsule()).padding(10) }
            }
        }.frame(maxHeight: 360).padding(.horizontal, 12).padding(.top, 4)
    }

    private var playbackBar: some View {
        HStack(spacing: 18) {
            Spacer(); Button { model.seek(by: -1) } label: { Image(systemName: "gobackward.10") }
            Button { model.playPause() } label: { Image(systemName: model.isPlaying ? "pause.fill" : "play.fill").font(.title3).frame(width: 44, height: 34).background(.thinMaterial, in: Capsule()) }
            Button { model.seek(by: 1) } label: { Image(systemName: "goforward.10") }
            Text(selectedTimeLabel).font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 92, alignment: .leading); Spacer()
        }.padding(.vertical, 8).disabled(model.selectedClip == nil)
    }

    private var timelineArea: some View {
        VStack(spacing: 8) {
            HStack { Label("Таймлайн", systemImage: "timeline.selection").font(.caption.weight(.semibold)); Spacer(); Button { model.timelineZoom = max(0.7, model.timelineZoom - 0.25) } label: { Image(systemName: "minus.magnifyingglass") }; Button { model.timelineZoom = min(2.5, model.timelineZoom + 0.25) } label: { Image(systemName: "plus.magnifyingglass") } }.foregroundStyle(.secondary).padding(.horizontal, 16)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    ForEach(Array(model.clips.enumerated()), id: \.element.id) { index, clip in TimelineClipView(clip: clip, index: index, selected: clip.id == model.selectedClipID, zoom: model.timelineZoom).onTapGesture { model.selectClip(clip.id) } }
                    Button { model.isImporting = true } label: { Image(systemName: "plus").font(.title3.weight(.semibold)).frame(width: 44, height: 54).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous)) }
                }.padding(.horizontal, 14).padding(.vertical, 5)
            }
            if model.selectedClip != nil {
                HStack(spacing: 8) { compactAction("chevron.left", "Назад") { model.moveSelectedClip(-1) }; compactAction("scissors", "Split") { model.splitSelectedClip() }; compactAction("plus.square.on.square", "Копия") { model.duplicateSelectedClip() }; compactAction("chevron.right", "Вперёд") { model.moveSelectedClip(1) }; compactAction("trash", "Удалить", role: .destructive) { model.deleteSelectedClip() } }.padding(.horizontal, 12)
            }
        }.padding(.vertical, 10).background(.regularMaterial).clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous)).padding(.horizontal, 8)
    }

    private var bottomToolBar: some View {
        ScrollView(.horizontal, showsIndicators: false) { HStack(spacing: 5) { editorTool("scissors", "Обрезка", .trim); editorTool("speedometer", "Скорость", .speed); editorTool("waveform", "Аудио", .audio); editorTool("textformat", "Текст", .text); editorTool("camera.filters", "Фильтры", .filters); editorTool("slider.horizontal.3", "Настройка", .adjust); editorTool("wand.and.stars", "Улучшить", .enhance) }.padding(.horizontal, 10) }.padding(.vertical, 8).background(.ultraThinMaterial).disabled(model.clips.isEmpty)
    }

    private var exportOverlay: some View { ZStack { Color.black.opacity(0.28).ignoresSafeArea(); VStack(spacing: 14) { ProgressView(value: model.exportProgress).progressViewStyle(.linear).frame(width: 220); Text("Экспорт \(Int(model.exportProgress * 100))%").font(.headline); Text("Не закрывайте VeloCut").font(.caption).foregroundStyle(.secondary) }.padding(24).background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous)) } }
    private var selectedTimeLabel: String { guard let clip = model.selectedClip else { return "0:00 / 0:00" }; return "\(format(max(0, model.currentTime - clip.trimStart))) / \(format(clip.sourceDuration))" }
    private func editorTool(_ icon: String, _ title: String, _ tool: InspectorTool) -> some View { Button { inspector = tool; model.haptic(.selection) } label: { VStack(spacing: 5) { Image(systemName: icon).font(.system(size: 17, weight: .medium)).frame(height: 22); Text(title).font(.caption2) }.frame(width: 72, height: 52).contentShape(Rectangle()) }.buttonStyle(.plain) }
    private func compactAction(_ icon: String, _ title: String, role: ButtonRole? = nil, action: @escaping () -> Void) -> some View { Button(role: role, action: action) { VStack(spacing: 3) { Image(systemName: icon); Text(title).font(.system(size: 9)) }.frame(maxWidth: .infinity).frame(height: 42).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous)) }.buttonStyle(.plain) }
    private func format(_ seconds: Double) -> String { let v = max(0, Int(seconds.rounded())); return String(format: "%d:%02d", v / 60, v % 60) }
}

struct TimelineClipView: View {
    let clip: EditorClip; let index: Int; let selected: Bool; let zoom: Double
    var body: some View {
        let width = min(220, max(72, clip.outputDuration * 14 * zoom))
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous).fill(selected ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.12))
            HStack(spacing: 3) { ForEach(0..<max(2, Int(width / 26)), id: \.self) { _ in RoundedRectangle(cornerRadius: 4).fill(Color.secondary.opacity(0.22)).overlay { Image(systemName: "play.rectangle.fill").font(.caption2).foregroundStyle(.secondary) } } }.padding(5)
            VStack { HStack { Text("\(index + 1)").font(.system(size: 9, weight: .bold)).padding(.horizontal, 5).padding(.vertical, 3).background(.ultraThinMaterial, in: Capsule()); Spacer(); Text("\(clip.speed, specifier: "%g")×").font(.system(size: 9, weight: .semibold)) }; Spacer(); HStack { Text(clip.name).font(.system(size: 9, weight: .medium)).lineLimit(1); Spacer(); Text(format(clip.outputDuration)).font(.system(size: 9).monospacedDigit()) } }.padding(6)
        }.frame(width: width, height: 58).overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(selected ? Color.accentColor : Color.clear, lineWidth: 2) }
    }
    private func format(_ seconds: Double) -> String { let v = max(0, Int(seconds.rounded())); return String(format: "%d:%02d", v / 60, v % 60) }
}

struct InspectorSheet: View {
    let tool: InspectorTool
    @ObservedObject var model: EditorViewModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Group { switch tool { case .trim: trimView; case .speed: speedView; case .audio: audioView; case .text: textView; case .filters: filtersView; case .adjust: adjustView; case .enhance: enhanceView; case .export: exportView } }
                .padding(.horizontal, 18).navigationTitle(title).navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } } }
        }
    }
    private var title: String { switch tool { case .trim: return "Обрезка"; case .speed: return "Скорость"; case .audio: return "Аудио"; case .text: return "Текст"; case .filters: return "Фильтры"; case .adjust: return "Настройка"; case .enhance: return "Улучшение"; case .export: return "Экспорт" } }
    private var trimView: some View {
        VStack(spacing: 22) { if let clip = model.selectedClip { valueSlider(title: "Начало", value: Binding(get: { model.selectedClip?.trimStart ?? 0 }, set: { model.setTrimStart($0) }), range: 0...max(0.1, clip.duration), suffix: time(model.selectedClip?.trimStart ?? 0)); valueSlider(title: "Конец", value: Binding(get: { model.selectedClip?.trimEnd ?? clip.duration }, set: { model.setTrimEnd($0) }), range: 0...max(0.1, clip.duration), suffix: time(model.selectedClip?.trimEnd ?? clip.duration)); HStack { Label("После обрезки", systemImage: "clock"); Spacer(); Text(time(clip.outputDuration)).monospacedDigit() }.font(.subheadline).foregroundStyle(.secondary); Button { model.splitSelectedClip() } label: { Label("Разделить по текущему курсору", systemImage: "scissors").frame(maxWidth: .infinity) }.buttonStyle(.borderedProminent) }; Spacer() }.padding(.top, 18)
    }
    private var speedView: some View {
        VStack(spacing: 20) { Text("\(model.selectedClip?.speed ?? 1, specifier: "%.2f")×").font(.system(size: 38, weight: .semibold, design: .rounded)); Slider(value: Binding(get: { model.selectedClip?.speed ?? 1 }, set: { model.setSpeed($0) }), in: 0.1...5, step: 0.05); HStack { ForEach([0.25, 0.5, 1.0, 1.5, 2.0, 3.0, 5.0], id: \.self) { value in Button("\(value, specifier: "%g")×") { model.setSpeed(value) }.font(.caption.weight(.semibold)).buttonStyle(.bordered).tint(abs((model.selectedClip?.speed ?? 1) - value) < 0.001 ? .accentColor : .secondary) } }; Label("Скорость меняет длительность видео и звука синхронно.", systemImage: "info.circle").font(.caption).foregroundStyle(.secondary); Spacer() }.padding(.top, 18)
    }
    private var audioView: some View {
        VStack(spacing: 20) { valueSlider(title: "Громкость клипа", value: Binding(get: { model.selectedClip?.volume ?? 1 }, set: { model.setVolume($0) }), range: 0...2, suffix: "\(Int((model.selectedClip?.volume ?? 1) * 100))%"); Divider(); HStack { VStack(alignment: .leading, spacing: 3) { Text("Музыка").font(.headline); Text(model.musicName ?? "Не добавлена").font(.caption).foregroundStyle(.secondary).lineLimit(1) }; Spacer(); Button(model.musicURL == nil ? "Добавить" : "Заменить") { model.isAudioImporting = true }.buttonStyle(.borderedProminent) }; if model.musicURL != nil { valueSlider(title: "Громкость музыки", value: $model.musicVolume, range: 0...1.5, suffix: "\(Int(model.musicVolume * 100))%") }; Spacer() }.padding(.top, 18)
    }
    private var textView: some View {
        VStack(spacing: 18) { TextField("Введите текст", text: $model.overlayText, axis: .vertical).textFieldStyle(.roundedBorder).lineLimit(1...3).onTapGesture { model.registerUndo() }; valueSlider(title: "Размер", value: $model.overlayTextSize, range: 18...72, suffix: "\(Int(model.overlayTextSize))"); valueSlider(title: "Положение", value: $model.overlayTextY, range: 0.15...0.9, suffix: ""); HStack { ForEach([(0.2, "Верх"), (0.5, "Центр"), (0.82, "Низ")], id: \.0) { item in Button(item.1) { model.overlayTextY = item.0 }.buttonStyle(.bordered) } }; Spacer() }.padding(.top, 18)
    }
    private var filtersView: some View {
        ScrollView(.horizontal, showsIndicators: false) { HStack(spacing: 12) { ForEach(EditorFilter.allCases) { filter in Button { model.setFilter(filter) } label: { VStack(spacing: 8) { RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.thinMaterial).frame(width: 86, height: 86).overlay { Image(systemName: filter.systemImage).font(.system(size: 30)) }.overlay { RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(model.selectedFilter == filter ? Color.accentColor : Color.clear, lineWidth: 3) }; Text(filter.rawValue).font(.caption) } }.buttonStyle(.plain) } }.padding(.vertical, 20) }
    }
    private var adjustView: some View {
        VStack(spacing: 20) { valueSlider(title: "Яркость", value: Binding(get: { model.brightness }, set: { model.updateColor(brightness: $0) }), range: -0.35...0.35, suffix: "\(Int(model.brightness * 100))"); valueSlider(title: "Контраст", value: Binding(get: { model.contrast }, set: { model.updateColor(contrast: $0) }), range: 0.5...1.7, suffix: "\(Int((model.contrast - 1) * 100))"); valueSlider(title: "Насыщенность", value: Binding(get: { model.saturation }, set: { model.updateColor(saturation: $0) }), range: 0...2, suffix: "\(Int((model.saturation - 1) * 100))"); Button("Сбросить настройки") { model.resetColor() }.buttonStyle(.bordered); Spacer() }.padding(.top, 18)
    }
    private var enhanceView: some View {
        VStack(spacing: 20) { Image(systemName: "wand.and.stars.inverse").font(.system(size: 42)).symbolRenderingMode(.hierarchical).foregroundStyle(Color.accentColor); Text("Локальное улучшение").font(.title3.weight(.semibold)); Text("Шумоподавление, повышение резкости и восстановление деталей выполняются при предпросмотре и экспорте.").font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center); valueSlider(title: "Интенсивность", value: Binding(get: { model.enhanceAmount }, set: { model.setEnhance($0) }), range: 0...1, suffix: "\(Int(model.enhanceAmount * 100))%"); Spacer() }.padding(.top, 18)
    }
    private var exportView: some View {
        VStack(spacing: 18) { Picker("Качество", selection: $model.exportQuality) { ForEach(ExportQuality.allCases) { q in Text(q.rawValue).tag(q) } }.pickerStyle(.segmented); VStack(spacing: 12) { exportRow("Длительность", time(model.projectDuration)); exportRow("Клипы", "\(model.clips.count)"); exportRow("Фильтр", model.selectedFilter.rawValue); exportRow("Текст", model.overlayText.isEmpty ? "Нет" : "Да"); exportRow("Музыка", model.musicURL == nil ? "Нет" : "Да") }.padding(16).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous)); Button { dismiss(); model.exportProject() } label: { Label("Экспортировать \(model.exportQuality.rawValue)", systemImage: "square.and.arrow.up").font(.headline).frame(maxWidth: .infinity).frame(height: 48) }.buttonStyle(.borderedProminent).disabled(model.isExporting || model.clips.isEmpty); Spacer() }.padding(.top, 18)
    }
    private func valueSlider(title: String, value: Binding<Double>, range: ClosedRange<Double>, suffix: String) -> some View { VStack(spacing: 8) { HStack { Text(title).font(.subheadline.weight(.medium)); Spacer(); if !suffix.isEmpty { Text(suffix).font(.caption.monospacedDigit()).foregroundStyle(.secondary) } }; Slider(value: value, in: range) } }
    private func exportRow(_ title: String, _ value: String) -> some View { HStack { Text(title).foregroundStyle(.secondary); Spacer(); Text(value).fontWeight(.medium) }.font(.subheadline) }
    private func time(_ seconds: Double) -> String { let v = max(0, Int(seconds.rounded())); return String(format: "%d:%02d", v / 60, v % 60) }
}

struct ProjectInfoSheet: View {
    @ObservedObject var model: EditorViewModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack { List { Section("Проект") { LabeledContent("Клипы", value: "\(model.clips.count)"); LabeledContent("Длительность", value: format(model.projectDuration)); LabeledContent("Качество экспорта", value: model.exportQuality.rawValue) }; Section("VeloCut") { Label("Нативный интерфейс SwiftUI", systemImage: "iphone"); Label("Монтаж и экспорт AVFoundation", systemImage: "film"); Label("Фильтры Core Image", systemImage: "camera.filters") } }.navigationTitle("Проект").navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } } } }
    }
    private func format(_ seconds: Double) -> String { let v = max(0, Int(seconds.rounded())); return String(format: "%d:%02d", v / 60, v % 60) }
}

@main
struct VeloCutAIApp: App {
    var body: some Scene { WindowGroup { EditorView().tint(.blue) } }
}
