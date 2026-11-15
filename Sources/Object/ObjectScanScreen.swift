import SwiftUI
import AVFoundation

final class PreviewContainer: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var preview: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
}

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewContainer {
        let container = PreviewContainer()
        container.backgroundColor = .black
        container.preview.session = session
        container.preview.videoGravity = .resizeAspectFill
        return container
    }

    func updateUIView(_ uiView: PreviewContainer, context: Context) {
        if uiView.preview.session !== session {
            uiView.preview.session = session
        }
    }
}

struct ObjectScanScreen: View {
    @EnvironmentObject private var store: ScanStore
    @Environment(\.dismiss) private var dismiss

    @StateObject private var capture = PhotoCaptureService()
    @StateObject private var runner = PhotogrammetryRunner()

    private enum Stage { case intro, capture, rebuild, done }
    @State private var stage: Stage = .intro
    @State private var asset: ScanAsset?
    @State private var folder: URL?
    @State private var autoCapture = true
    @State private var detail: PhotogrammetryRunner.Detail = .full
    @State private var showShare = false
    @State private var shareItems: [Any] = []
    @State private var showPreview = false

    private let ticker = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()

            switch stage {
            case .intro: introView
            case .capture: captureView
            case .rebuild: rebuildView
            case .done: doneView
            }

            VStack {
                ScanOverlayTopBar(
                    title: "物体重建",
                    subtitle: subtitle,
                    onClose: {
                        capture.stop()
                        runner.cancel()
                        dismiss()
                    }
                )
                Spacer()
            }
        }
        .onAppear { capture.configureIfNeeded() }
        .onReceive(ticker) { _ in
            guard stage == .capture, autoCapture, capture.canShoot else { return }
            capture.shoot()
        }
        .onReceive(runner.$producedURL) { url in
            guard url != nil else { return }
            finishRebuild()
        }
        .sheet(isPresented: $showShare) { ShareSheet(items: shareItems) }
        .sheet(isPresented: $showPreview) {
            if let asset, let model = asset.modelFile {
                QuickLookView(url: store.fileURL(asset, model)).ignoresSafeArea()
            }
        }
    }

    private var subtitle: String {
        switch stage {
        case .intro: return "在同一水平面上绕物体转 2–3 圈，覆盖高、中、低三个高度"
        case .capture: return "已拍 \(capture.capturedCount) 张 · 目标 80 张以上"
        case .rebuild: return runner.stage
        case .done: return "重建完成"
        }
    }

    // MARK: 引导页

    private var introView: some View {
        VStack(alignment: .leading, spacing: 18) {
            Spacer()
            Text("把物体放在纹理丰富的地面")
                .font(.system(size: 26, weight: .bold))
            Text("激光雷达负责尺度与深度，摄影测量负责纹理与细节。两者叠起来，才能出这种精度的模型。")
                .font(.subheadline)
                .foregroundStyle(Theme.textDim)

            VStack(alignment: .leading, spacing: 10) {
                bullet("slowmo", "匀速绕圈，同一高度拍满一圈再换高度")
                bullet("camera.metering.center.weighted", "物体占画面 60% 以上，别让背景抢主体")
                bullet("sun.max", "柔光、无强反光；反光面重建会崩")
                bullet("square.stack.3d.up", "至少 80 张，翻过去能看到顶面和底面各来一圈")
            }
            .padding(.vertical, 6)

            HStack(spacing: 8) {
                ForEach(PhotogrammetryRunner.Detail.allCases, id: \.self) { item in
                    Button {
                        detail = item
                    } label: {
                        Text(item.title)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(detail == item ? .black : .white)
                            .padding(.vertical, 10)
                            .frame(maxWidth: .infinity)
                            .background(RoundedRectangle(cornerRadius: 12).fill(detail == item ? Theme.warm : Theme.cardSoft))
                    }
                    .buttonStyle(.plain)
                }
            }

            BigActionButton(title: "开始拍摄", symbol: "camera.aperture", tint: Theme.warm) {
                let (newAsset, dir) = store.makeFolder(for: .object, name: ScanNaming.stamp("物体"))
                asset = newAsset
                folder = dir
                capture.makeDirectory(dir.appendingPathComponent("images", isDirectory: true))
                capture.start()
                stage = .capture
            }
            Spacer()
        }
        .padding(.horizontal, 20)
    }

    private func bullet(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol).foregroundStyle(Theme.warm).frame(width: 22)
            Text(text).font(.system(size: 14)).foregroundStyle(.white.opacity(0.86))
        }
    }

    // MARK: 拍摄页

    private var captureView: some View {
        ZStack {
            CameraPreview(session: capture.session).ignoresSafeArea()

            VStack {
                Spacer()
                ZStack {
                    Circle().stroke(Color.white.opacity(0.35), lineWidth: 2).frame(width: 150, height: 150)
                    Circle().stroke(Theme.warm, lineWidth: 3)
                        .frame(width: 150, height: 150)
                        .trim(from: 0, to: min(Double(capture.capturedCount) / 80.0, 1.0))
                        .rotationEffect(.degrees(-90))
                    Text("\(capture.capturedCount)")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }
                .padding(.bottom, 18)

                HStack(spacing: 12) {
                    Button {
                        autoCapture.toggle()
                    } label: {
                        Label(autoCapture ? "连拍开" : "手动", systemImage: autoCapture ? "repeat" : "hand.tap")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.vertical, 12)
                            .frame(maxWidth: .infinity)
                            .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.12)))
                    }
                    .buttonStyle(.plain)

                    Button {
                        capture.shoot()
                    } label: {
                        Text("拍一张")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.black)
                            .padding(.vertical, 12)
                            .frame(maxWidth: .infinity)
                            .background(RoundedRectangle(cornerRadius: 14).fill(Theme.warm))
                    }
                    .buttonStyle(.plain)

                    Button {
                        guard capture.capturedCount >= 20 else {
                            capture.lastError = "至少拍 20 张再重建，80 张以上效果最好"
                            return
                        }
                        capture.stop()
                        startRebuild()
                    } label: {
                        Text("重建")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.black)
                            .padding(.vertical, 12)
                            .frame(maxWidth: .infinity)
                            .background(RoundedRectangle(cornerRadius: 14).fill(Theme.accent))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 18)

                if let error = capture.lastError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .padding(.top, 6)
                }
            }
            .padding(.bottom, 28)
        }
    }

    // MARK: 重建页

    private var rebuildView: some View {
        VStack(spacing: 18) {
            Spacer()
            ZStack {
                Circle().stroke(Color.white.opacity(0.12), lineWidth: 6).frame(width: 180, height: 180)
                Circle()
                    .trim(from: 0, to: runner.progress)
                    .stroke(Theme.warm, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .frame(width: 180, height: 180)
                    .rotationEffect(.degrees(-90))
                Text("\(Int(runner.progress * 100))%")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
            }
            Text(runner.stage).font(.headline)
            Text("全精度重建通常要 2–8 分钟，手机上跑，数据不出设备")
                .font(.caption)
                .foregroundStyle(Theme.textDim)

            if let error = runner.errorText {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                BigActionButton(title: "返回拍摄", symbol: "arrow.uturn.backward") {
                    runner.errorText = nil
                    capture.start()
                    stage = .capture
                }
                .padding(.horizontal, 24)
            }
            Spacer()
        }
    }

    // MARK: 结果页

    private var doneView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "cube.transparent")
                .font(.system(size: 52))
                .foregroundStyle(Theme.warm)
            Text("重建完成").font(.system(size: 24, weight: .bold))
            if let asset {
                Text(asset.stats).font(.subheadline).foregroundStyle(Theme.textDim)
            }
            HStack(spacing: 10) {
                Button { showPreview = true } label: {
                    Label("AR 预览", systemImage: "arkit").frame(maxWidth: .infinity)
                }
                .buttonStyle(GlassButtonStyle())
                Button {
                    shareItems = collectFiles()
                    showShare = true
                } label: {
                    Label("导出", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                }
                .buttonStyle(GlassButtonStyle())
                Button { dismiss() } label: {
                    Label("完成", systemImage: "checkmark").frame(maxWidth: .infinity)
                }
                .buttonStyle(GlassButtonStyle(tint: Theme.accent))
            }
            .padding(.horizontal, 18)
            Spacer()
        }
    }

    // MARK: 流程

    private func startRebuild() {
        guard let folder else { return }
        stage = .rebuild
        let images = folder.appendingPathComponent("images", isDirectory: true)
        let output = folder.appendingPathComponent("object.usdz")
        runner.run(imagesDirectory: images, outputURL: output, detail: detail)
    }

    private func finishRebuild() {
        guard var asset else { return }
        let folderURL = store.folder(for: asset.id)
        let modelPath = folderURL.appendingPathComponent("object.usdz").path
        guard FileManager.default.fileExists(atPath: modelPath) else { return }
        let photos = (try? FileManager.default.contentsOfDirectory(atPath:
            folderURL.appendingPathComponent("images", isDirectory: true).path))?.count ?? 0
        asset.modelFile = "object.usdz"
        asset.sidecarFiles = ["images", "meta.json"]
        asset.summaryLines = [
            "照片 \(photos) 张 · \(detail.title)重建",
            "Apple 摄影测量 + 激光雷达尺度约束",
            "输出 USDZ（含贴图），可直接在「文件」App 里取走"
        ]
        asset.stats = "\(photos) 张照片 · USDZ"
        store.save(asset)
        self.asset = asset
        stage = .done
    }

    private func collectFiles() -> [Any] {
        guard let asset else { return [] }
        var items: [Any] = []
        for file in ([asset.modelFile].compactMap { $0 } + asset.sidecarFiles) {
            let url = store.fileURL(asset, file)
            if FileManager.default.fileExists(atPath: url.path) { items.append(url) }
        }
        return items
    }
}
