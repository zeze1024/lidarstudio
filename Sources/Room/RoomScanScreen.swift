import SwiftUI
import UIKit
import RoomPlan

// MARK: - RoomPlan 控制器

class RoomScanController: UIViewController, RoomCaptureViewDelegate {
    private let captureSession = RoomCaptureSession()
    private let captureView = RoomCaptureView(frame: .zero)

    var onFinish: ((CapturedRoom) -> Void)?
    var onFail: ((String) -> Void)?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        captureView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(captureView)
        NSLayoutConstraint.activate([
            captureView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            captureView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            captureView.topAnchor.constraint(equalTo: view.topAnchor),
            captureView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        captureView.captureSession = captureSession
        captureView.delegate = self
        captureView.isModelEnabled = true
    }

    func startScanning() {
        var config = RoomCaptureSession.Configuration()
        config.isCoachingEnabled = true
        captureSession.run(configuration: config)
    }

    func stopScanning() {
        captureSession.stop()
    }

    // MARK: RoomCaptureViewDelegate

    func captureView(shouldPresent roomDataForProcessing: CapturedRoomData, error: (any Error)?) -> Bool {
        if let error {
            onFail?(error.localizedDescription)
            return false
        }
        return true
    }

    func captureView(didPresent processedResult: CapturedRoom, error: (any Error)?) {
        if let error {
            onFail?(error.localizedDescription)
            return
        }
        onFinish?(processedResult)
    }
}

struct RoomCaptureSurface: UIViewControllerRepresentable {
    let controller: RoomScanController

    func makeUIViewController(context: Context) -> RoomScanController { controller }
    func updateUIViewController(_ uiViewController: RoomScanController, context: Context) {}
}

// MARK: - 报告

struct RoomReport {
    var lines: [String] = []
    var stats: String = ""
    var text: String = ""
    var wallCount: Int = 0
    var objectCount: Int = 0
}

enum RoomReportBuilder {
    static func make(from room: CapturedRoom) -> RoomReport {
        var report = RoomReport()
        var out: [String] = []

        var perimeter: Float = 0
        var wallArea: Float = 0
        var heightSum: Float = 0
        for wall in room.walls {
            let d = wall.dimensions
            let width = CGFloat(max(d.x, d.y))
            let height = CGFloat(min(d.x, d.y))
            perimeter += Float(width)
            if height > 0.5 { wallArea += Float(width * height); heightSum += Float(height) }
        }
        let avgHeight = room.walls.isEmpty ? 0 : heightSum / Float(room.walls.count)

        var floorArea: Float = 0
        for floor in room.floors {
            floorArea += floor.dimensions.x * floor.dimensions.y
        }

        report.wallCount = room.walls.count
        report.objectCount = room.objects.count

        out.append("墙体：\(room.walls.count) 面，周长约 \(fmt(perimeter, 1)) m")
        if avgHeight > 0 { out.append("平均层高：\(fmt(avgHeight, 2)) m") }
        if wallArea > 0 { out.append("墙面总面积：\(fmt(wallArea, 1)) m²") }
        out.append("地面面积：\(fmt(floorArea, 1)) m²")
        out.append("门：\(room.doors.count) 个，窗：\(room.windows.count) 个")

        if !room.objects.isEmpty {
            var byCategory: [String: Int] = [:]
            for object in room.objects {
                byCategory[object.category.rawValue, default: 0] += 1
            }
            let detail = byCategory
                .sorted { $0.value > $1.value }
                .map { "\($0.key) \($0.value)" }
                .joined(separator: "、")
            out.append("家具物件：\(room.objects.count) 件（\(detail)）")
        }

        var fine: [String] = []
        for object in room.objects.prefix(12) {
            let d = object.dimensions
            fine.append("\(object.category.rawValue) 约 \(fmt(Float(d.x) * 100, 0))×\(fmt(Float(d.y) * 100, 0))×\(fmt(Float(d.z) * 100, 0)) cm")
        }

        report.lines = out
        report.stats = "\(room.walls.count) 面墙 · \(fmt(floorArea, 1)) m² · \(room.objects.count) 件家具"

        var text = "LiDAR Studio 空间报告\n生成时间：\(Date())\n\n"
        text += out.joined(separator: "\n")
        if !fine.isEmpty {
            text += "\n\n物件尺寸（激光雷达实测，cm）\n" + fine.joined(separator: "\n")
        }
        text += "\n\n数据来源：Apple RoomPlan（iPhone 激光雷达 parametric 重建）\n"
        report.text = text
        return report
    }

    private static func fmt(_ value: Float, _ digits: Int) -> String {
        String(format: "%.\(digits)f", value)
    }
}

// MARK: - 会话包装

final class RoomSession: ObservableObject {
    @Published var instruction: String = "横向慢慢走，把每一面墙都扫进去；扫完点结束"
    @Published var room: CapturedRoom?
    @Published var errorText: String?

    let controller = RoomScanController()

    init() {
        controller.onFinish = { [weak self] room in
            self?.room = room
        }
        controller.onFail = { [weak self] message in
            self?.errorText = message
        }
    }
}

// MARK: - 界面

struct RoomScanScreen: View {
    @EnvironmentObject private var store: ScanStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var session = RoomSession()

    @State private var isScanning = false
    @State private var isProcessing = false
    @State private var savedAsset: ScanAsset?
    @State private var showPreview = false
    @State private var shareItems: [Any] = []
    @State private var showShare = false

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            RoomCaptureSurface(controller: session.controller).ignoresSafeArea()

            VStack {
                ScanOverlayTopBar(
                    title: "空间扫描",
                    subtitle: session.instruction,
                    onClose: { session.controller.stopScanning(); dismiss() }
                )
                Spacer()
                bottomControls
            }
            .padding(.bottom, 24)

            if isProcessing {
                processingOverlay
            }
        }
        .onReceive(session.$room) { room in
            guard let room else { return }
            isScanning = false
            isProcessing = false
            persist(room: room)
        }
        .onChange(of: session.errorText) { _, message in
            guard let message, !message.isEmpty else { return }
            isScanning = false
            isProcessing = false
        }
        .sheet(isPresented: $showPreview) {
            if let asset = savedAsset, let file = asset.modelFile {
                QuickLookView(url: store.fileURL(asset, file))
                    .ignoresSafeArea()
            }
        }
        .sheet(isPresented: $showShare) {
            ShareSheet(items: shareItems)
        }
    }

    private var bottomControls: some View {
        VStack(spacing: 10) {
            if let error = session.errorText, !error.isEmpty {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.white)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Color.red.opacity(0.35)))
                    .padding(.horizontal, 18)
            }

            if let asset = savedAsset {
                HStack(spacing: 10) {
                    Button {
                        showPreview = true
                    } label: {
                        Label("AR 预览", systemImage: "arkit")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(GlassButtonStyle())

                    Button {
                        shareItems = collectFiles(for: asset)
                        showShare = true
                    } label: {
                        Label("导出", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(GlassButtonStyle())

                    Button {
                        dismiss()
                    } label: {
                        Label("完成", systemImage: "checkmark")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(GlassButtonStyle(tint: Theme.accent))
                }
                .padding(.horizontal, 18)
            } else {
                HStack(spacing: 12) {
                    if isScanning {
                        Button {
                            isProcessing = true
                            session.instruction = "正在重建房间模型…"
                            session.controller.stopScanning()
                        } label: {
                            Text("结束扫描")
                                .font(.system(size: 17, weight: .bold))
                                .foregroundStyle(.black)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.warm))
                        }
                        .buttonStyle(.plain)
                    } else {
                        Button {
                            isScanning = true
                            session.errorText = nil
                            session.room = nil
                            session.instruction = "慢慢地转一圈，让提示框覆盖住墙面"
                            session.controller.startScanning()
                        } label: {
                            Text("开始扫描")
                                .font(.system(size: 17, weight: .bold))
                                .foregroundStyle(.black)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.accent))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 18)
            }
        }
    }

    private var processingOverlay: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()
            VStack(spacing: 14) {
                ProgressView().controlSize(.large).tint(Theme.accent)
                Text("RoomPlan 正在参数化建模").font(.headline)
                Text("墙面、门窗、家具都会被识别成可测量实体").font(.caption).foregroundStyle(Theme.textDim)
            }
            .padding(24)
            .background(RoundedRectangle(cornerRadius: 20).fill(Theme.card))
        }
    }

    private func persist(room: CapturedRoom) {
        let (asset, folder) = store.makeFolder(for: .room, name: ScanNaming.stamp("空间"))
        let report = RoomReportBuilder.make(from: room)
        var modelName: String?
        do {
            let usdz = try room.usdzData
            let url = folder.appendingPathComponent("room.usdz")
            try usdz.write(to: url, options: .atomic)
            modelName = "room.usdz"
        } catch {
            session.errorText = "USDZ 导出失败：\(error.localizedDescription)"
        }
        let reportURL = folder.appendingPathComponent("room-report.txt")
        try? report.text.write(to: reportURL, atomically: true, encoding: .utf8)

        var final = asset
        final.modelFile = modelName
        final.sidecarFiles = ["room-report.txt"]
        final.summaryLines = report.lines
        final.stats = report.stats
        store.save(final)
        savedAsset = final
    }

    private func collectFiles(for asset: ScanAsset) -> [Any] {
        var items: [Any] = []
        if let model = asset.modelFile {
            items.append(store.fileURL(asset, model))
        }
        for side in asset.sidecarFiles {
            let url = store.fileURL(asset, side)
            if FileManager.default.fileExists(atPath: url.path) { items.append(url) }
        }
        return items
    }
}

// MARK: - 玻璃按钮

struct GlassButtonStyle: ButtonStyle {
    var tint: Color = Color.white.opacity(0.14)

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Color.white)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(tint)
            )
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
