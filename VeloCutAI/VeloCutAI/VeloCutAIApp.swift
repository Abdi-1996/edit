import SwiftUI
import AVKit
import AVFoundation
import UniformTypeIdentifiers
import UIKit

struct EditorClip {
    let url: URL
    var name: String
    var duration: Double
    var trimStart: Double
    var trimEnd: Double
    var speed: Double
}

@MainActor
final class EditorViewModel: ObservableObject {
    @Published var clip: EditorClip?
    @Published var player = AVPlayer()
    @Published var isImporting = false
    @Published var isExporting = false
    @Published var exportedURL: URL?
    @Published var errorMessage: String?

    func importVideo(_ url: URL) {
        Task {
            do {
                let asset = AVURLAsset(url: url)
                let time = try await asset.load(.duration)
                let duration = max(0.1, CMTimeGetSeconds(time))
                clip = EditorClip(url: url, name: url.lastPathComponent, duration: duration, trimStart: 0, trimEnd: duration, speed: 1)
                player.replaceCurrentItem(with: AVPlayerItem(url: url))
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func setStart(_ value: Double) {
        guard var c = clip else { return }
        c.trimStart = min(max(0, value), max(0, c.trimEnd - 0.05))
        clip = c
        player.seek(to: CMTime(seconds: c.trimStart, preferredTimescale: 600))
    }

    func setEnd(_ value: Double) {
        guard var c = clip else { return }
        c.trimEnd = max(min(c.duration, value), min(c.duration, c.trimStart + 0.05))
        clip = c
        player.seek(to: CMTime(seconds: c.trimEnd, preferredTimescale: 600))
    }

    func setSpeed(_ value: Double) {
        guard var c = clip else { return }
        c.speed = value
        clip = c
    }

    func export() {
        guard let c = clip else { return }
        isExporting = true
        exportedURL = nil
        Task {
            do {
                exportedURL = try await exportVideo(c)
            } catch {
                errorMessage = error.localizedDescription
            }
            isExporting = false
        }
    }

    private func exportVideo(_ clip: EditorClip) async throws -> URL {
        let asset = AVURLAsset(url: clip.url)
        let composition = AVMutableComposition()
        let videos = try await asset.loadTracks(withMediaType: .video)
        guard let sourceVideo = videos.first,
              let video = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw NSError(domain: "VeloCut", code: 1, userInfo: [NSLocalizedDescriptionKey: "Видеодорожка не найдена"])
        }

        let start = max(0, clip.trimStart)
        let selected = max(0.05, clip.trimEnd - start)
        let range = CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 600), duration: CMTime(seconds: selected, preferredTimescale: 600))
        try video.insertTimeRange(range, of: sourceVideo, at: .zero)
        video.preferredTransform = try await sourceVideo.load(.preferredTransform)

        let audios = try await asset.loadTracks(withMediaType: .audio)
        if let sourceAudio = audios.first,
           let audio = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
            try? audio.insertTimeRange(range, of: sourceAudio, at: .zero)
        }

        let inserted = CMTimeRange(start: .zero, duration: CMTime(seconds: selected, preferredTimescale: 600))
        composition.scaleTimeRange(inserted, toDuration: CMTime(seconds: selected / max(0.1, clip.speed), preferredTimescale: 600))

        let output = FileManager.default.temporaryDirectory.appendingPathComponent("VeloCut-\(UUID().uuidString).mp4")
        guard let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
            throw NSError(domain: "VeloCut", code: 2, userInfo: [NSLocalizedDescriptionKey: "Не удалось создать экспорт"])
        }
        session.outputURL = output
        session.outputFileType = .mp4
        session.shouldOptimizeForNetworkUse = true

        await withCheckedContinuation { continuation in
            session.exportAsynchronously { continuation.resume() }
        }
        guard session.status == .completed else {
            throw session.error ?? NSError(domain: "VeloCut", code: 3, userInfo: [NSLocalizedDescriptionKey: "Ошибка экспорта"])
        }
        return output
    }
}

struct PlayerView: UIViewControllerRepresentable {
    let player: AVPlayer
    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let vc = AVPlayerViewController()
        vc.player = player
        vc.videoGravity = .resizeAspect
        return vc
    }
    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        uiViewController.player = player
    }
}

struct VideoPicker: UIViewControllerRepresentable {
    let onPick: (URL) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(onPick) }
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let vc = UIDocumentPickerViewController(forOpeningContentTypes: [.movie, .mpeg4Movie, .quickTimeMovie], asCopy: true)
        vc.delegate = context.coordinator
        return vc
    }
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL) -> Void
        init(_ onPick: @escaping (URL) -> Void) { self.onPick = onPick }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            if let url = urls.first { onPick(url) }
        }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

struct EditorView: View {
    @StateObject private var model = EditorViewModel()
    @State private var showShare = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                VStack(spacing: 12) {
                    HStack {
                        VStack(alignment: .leading) {
                            Text("VeloCut AI").font(.headline.bold())
                            Text(model.clip?.name ?? "Новый проект").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        Button("Импорт", systemImage: "plus") { model.isImporting = true }.buttonStyle(.bordered)
                        Button { model.export() } label: {
                            if model.isExporting { ProgressView() } else { Label("Экспорт", systemImage: "square.and.arrow.up") }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.clip == nil || model.isExporting)
                    }
                    .padding(.horizontal)

                    Group {
                        if model.clip != nil {
                            PlayerView(player: model.player)
                        } else {
                            Button { model.isImporting = true } label: {
                                VStack(spacing: 12) {
                                    Image(systemName: "film.stack").font(.system(size: 48))
                                    Text("Добавьте видео").font(.title3.bold())
                                    Text("MP4 или MOV из приложения «Файлы»").foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                            }.buttonStyle(.plain)
                        }
                    }
                    .frame(maxHeight: .infinity)
                    .background(Color.white.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .padding(.horizontal)

                    if let clip = model.clip {
                        VStack(spacing: 10) {
                            HStack {
                                Text("Начало").frame(width: 55, alignment: .leading)
                                Slider(value: Binding(get: { model.clip?.trimStart ?? 0 }, set: model.setStart), in: 0...max(0.1, clip.duration))
                                Text(time(clip.trimStart)).monospacedDigit().frame(width: 48)
                            }
                            HStack {
                                Text("Конец").frame(width: 55, alignment: .leading)
                                Slider(value: Binding(get: { model.clip?.trimEnd ?? clip.duration }, set: model.setEnd), in: 0...max(0.1, clip.duration))
                                Text(time(clip.trimEnd)).monospacedDigit().frame(width: 48)
                            }
                            HStack {
                                Text("Скорость")
                                Spacer()
                                ForEach([0.5, 1.0, 1.5, 2.0, 3.0], id: \.self) { speed in
                                    Button("\(speed, specifier: "%g")×") { model.setSpeed(speed) }
                                        .buttonStyle(.bordered)
                                        .tint(model.clip?.speed == speed ? .accentColor : .gray)
                                }
                            }
                        }
                        .font(.caption)
                        .padding(.horizontal)
                    }

                    HStack(spacing: 24) {
                        tool("scissors", "Обрезка")
                        tool("speedometer", "Скорость")
                        tool("waveform", "Аудио")
                        tool("textformat", "Текст")
                        tool("sparkles", "AI")
                    }
                    .padding(.vertical, 12)
                }
            }
            .preferredColorScheme(.dark)
            .sheet(isPresented: $model.isImporting) {
                VideoPicker { url in model.isImporting = false; model.importVideo(url) }
            }
            .sheet(isPresented: $showShare) {
                if let url = model.exportedURL { ShareSheet(url: url) }
            }
            .onChange(of: model.exportedURL) { _, value in if value != nil { showShare = true } }
            .alert("Ошибка", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
                Button("OK", role: .cancel) { model.errorMessage = nil }
            } message: { Text(model.errorMessage ?? "") }
        }
    }

    private func tool(_ icon: String, _ text: String) -> some View {
        VStack(spacing: 5) { Image(systemName: icon); Text(text).font(.caption2) }
    }
    private func time(_ seconds: Double) -> String {
        let value = max(0, Int(seconds.rounded()))
        return String(format: "%d:%02d", value / 60, value % 60)
    }
}

@main
struct VeloCutAIApp: App {
    var body: some Scene { WindowGroup { EditorView() } }
}
