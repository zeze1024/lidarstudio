import Foundation
import RealityKit

/// 在本机跑 Apple 摄影测量重建（Object Capture / PhotogrammetrySession）。
final class PhotogrammetryRunner: ObservableObject {
    @Published var progress: Double = 0
    @Published var stage: String = "准备中"
    @Published var isRunning = false
    @Published var producedURL: URL?
    @Published var errorText: String?

    private var session: PhotogrammetrySession?

    enum Detail: String, CaseIterable {
        case preview, medium, full
        var title: String {
            switch self {
            case .preview: return "预览"
            case .medium: return "中"
            case .full: return "全精度"
            }
        }
    }

    func run(imagesDirectory: URL, outputURL: URL, detail: Detail) {
        guard !isRunning else { return }
        isRunning = true
        progress = 0
        stage = "初始化重建会话"
        errorText = nil
        producedURL = nil

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            do {
                var config = PhotogrammetrySession.Configuration()
                config.sampleOrdering = .sequential
                config.featureSensitivity = .high
                let session = try PhotogrammetrySession(input: imagesDirectory, configuration: config)
                await MainActor.run { self.session = session }
                try session.process(requests: [
                    .modelFile(url: outputURL, detail: detail.requestDetail)
                ])

                for try await output in session.outputs {
                    switch output {
                    case let .requestProgress(_, fraction):
                        await MainActor.run {
                            self.progress = fraction
                            self.stage = "重建中 \(Int(fraction * 100))%"
                        }
                    case let .requestComplete(_, result):
                        if case let .modelFile(url) = result {
                            await MainActor.run {
                                self.producedURL = url
                                self.progress = 1
                                self.stage = "完成"
                            }
                        }
                    case .processingComplete:
                        await MainActor.run {
                            self.stage = "完成"
                            self.progress = 1
                        }
                    case let .requestError(_, error):
                        await MainActor.run {
                            self.errorText = error.localizedDescription
                            self.isRunning = false
                        }
                    case let .invalidSample(url, reason):
                        print("invalid sample \(url.lastPathComponent): \(reason)")
                    case let .skippedSample(url, reason):
                        print("skipped \(url.lastPathComponent): \(reason)")
                    default:
                        break
                    }
                }
                await MainActor.run { self.isRunning = false }
            } catch {
                await MainActor.run {
                    self.errorText = error.localizedDescription
                    self.isRunning = false
                    self.stage = "重建失败"
                }
            }
        }
    }

    func cancel() {
        session?.cancel()
        isRunning = false
    }
}

private extension PhotogrammetryRunner.Detail {
    var requestDetail: PhotogrammetrySession.Request.Detail {
        switch self {
        case .preview: return .preview
        case .medium: return .medium
        case .full: return .full
        }
    }
}
