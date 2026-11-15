import SwiftUI

struct RootView: View {
    @EnvironmentObject private var store: ScanStore

    @State private var showRoom = false
    @State private var showObject = false
    @State private var showMesh = false
    @State private var detail: ScanAsset?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header

                    VStack(spacing: 12) {
                        ModeCard(
                            kind: .room,
                            title: "空间扫描",
                            subtitle: "RoomPlan 参数化建模：墙、门窗、家具都变成可测实体",
                            badge: "USDZ + 尺寸报告"
                        ) { showRoom = true }

                        ModeCard(
                            kind: .object,
                            title: "物体重建",
                            subtitle: "摄影测量 + 激光雷达定尺度，输出带贴图的 USDZ",
                            badge: "全精度 USDZ"
                        ) { showObject = true }

                        ModeCard(
                            kind: .mesh,
                            title: "精网扫描",
                            subtitle: "逐帧深度融合：8 mm 体素稠密点云 + 三角网格",
                            badge: "OBJ + PLY"
                        ) { showMesh = true }
                    }

                    library
                }
                .padding(18)
                .padding(.bottom, 24)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
        }
        .fullScreenCover(isPresented: $showRoom) { RoomScanScreen().environmentObject(store) }
        .fullScreenCover(isPresented: $showObject) { ObjectScanScreen().environmentObject(store) }
        .fullScreenCover(isPresented: $showMesh) { MeshScanScreen().environmentObject(store) }
        .sheet(item: $detail) { asset in
            ScanDetailView(asset: asset).environmentObject(store)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("LiDAR STUDIO")
                        .font(.system(size: 30, weight: .black, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(colors: [Theme.accent, Theme.warm], startPoint: .leading, endPoint: .trailing)
                        )
                    Text("本机激光雷达三维重建 · 零服务器 · 零订阅")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textDim)
                }
                Spacer()
                Image(systemName: "arkit")
                    .font(.system(size: 24))
                    .foregroundStyle(Theme.accent)
            }

            HStack(spacing: 8) {
                capabilityChip(DeviceSupport.hasLiDAR ? "LiDAR 就绪" : "无激光雷达", ok: DeviceSupport.hasLiDAR)
                capabilityChip(DeviceSupport.supportsMeshReconstruction ? "网格重建" : "不支持", ok: DeviceSupport.supportsMeshReconstruction)
                capabilityChip(DeviceSupport.supportsPhotogrammetry ? "本机摄影测量" : "算力不足", ok: DeviceSupport.supportsPhotogrammetry)
            }
        }
        .padding(.top, 8)
    }

    private func capabilityChip(_ text: String, ok: Bool) -> some View {
        HStack(spacing: 5) {
            Circle().fill(ok ? Theme.accent : Color.orange).frame(width: 6, height: 6)
            Text(text).font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.8))
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(Capsule().fill(Theme.cardSoft))
    }

    private var library: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("扫描库").font(.system(size: 18, weight: .bold))
                Spacer()
                Text("\(store.scans.count) 个模型")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textDim)
            }

            if store.scans.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("还没有模型")
                        .font(.system(size: 15, weight: .semibold))
                    Text("找一个房间，或桌上一个杯子，扫一个试试。")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textDim)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .card()
            } else {
                ForEach(store.scans) { asset in
                    Button {
                        detail = asset
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: asset.kind.symbol)
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(asset.kind.tint)
                                .frame(width: 40, height: 40)
                                .background(RoundedRectangle(cornerRadius: 12).fill(Theme.cardSoft))

                            VStack(alignment: .leading, spacing: 3) {
                                Text(asset.name)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(.white)
                                Text(asset.stats.isEmpty ? asset.kind.title : asset.stats)
                                    .font(.system(size: 12))
                                    .foregroundStyle(Theme.textDim)
                            }
                            Spacer()
                            Text(store.sizeText(for: asset))
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.textDim)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Theme.textDim)
                        }
                        .card(padding: 12)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(role: .destructive) {
                            store.delete(asset)
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }
                }
            }
        }
    }
}

struct ModeCard: View {
    let kind: ScanKind
    let title: String
    let subtitle: String
    let badge: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(kind.tint.opacity(0.16))
                        .frame(width: 56, height: 56)
                    Image(systemName: kind.symbol)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(kind.tint)
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text(title).font(.system(size: 17, weight: .bold)).foregroundStyle(.white)
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textDim)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(badge)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(kind.tint)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(kind.tint.opacity(0.14)))
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.textDim)
            }
            .card()
        }
        .buttonStyle(.plain)
    }
}

struct ScanDetailView: View {
    @EnvironmentObject private var store: ScanStore
    @Environment(\.dismiss) private var dismiss

    let asset: ScanAsset

    @State private var showShare = false
    @State private var shareItems: [Any] = []
    @State private var showPreview = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 12) {
                        Image(systemName: asset.kind.symbol)
                            .font(.system(size: 22))
                            .foregroundStyle(asset.kind.tint)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(asset.name).font(.system(size: 20, weight: .bold))
                            Text(asset.stats).font(.system(size: 12)).foregroundStyle(Theme.textDim)
                        }
                        Spacer()
                    }

                    if !asset.summaryLines.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(asset.summaryLines, id: \.self) { line in
                                HStack(alignment: .top, spacing: 8) {
                                    Circle().fill(asset.kind.tint).frame(width: 5, height: 5).padding(.top, 6)
                                    Text(line).font(.system(size: 13)).foregroundStyle(.white.opacity(0.85))
                                }
                            }
                        }
                        .card()
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("文件").font(.system(size: 15, weight: .bold))
                        ForEach(fileNames, id: \.self) { name in
                            HStack {
                                Image(systemName: "doc")
                                Text(name).font(.system(size: 13))
                                Spacer()
                                Text(fileSize(name)).font(.system(size: 11)).foregroundStyle(Theme.textDim)
                            }
                            .foregroundStyle(.white.opacity(0.85))
                            .padding(.vertical, 6)
                        }
                        Text("在「文件」App → 我的 iPhone → LiDAR Studio 里可直接拷到电脑")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textDim)
                    }
                    .card()

                    VStack(spacing: 10) {
                        if let model = asset.modelFile, model.hasSuffix(".usdz") {
                            BigActionButton(title: "AR 预览", symbol: "arkit", tint: asset.kind.tint) {
                                showPreview = true
                            }
                        }
                        BigActionButton(title: "分享 / 导出", symbol: "square.and.arrow.up", tint: Theme.cardSoft) {
                            shareItems = collectAll()
                            showShare = true
                        }
                    }
                }
                .padding(18)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") { dismiss() }
                }
            }
        }
        .sheet(isPresented: $showShare) { ShareSheet(items: shareItems) }
        .sheet(isPresented: $showPreview) {
            if let model = asset.modelFile {
                QuickLookView(url: store.fileURL(asset, model)).ignoresSafeArea()
            }
        }
    }

    private var fileNames: [String] {
        ([asset.modelFile].compactMap { $0 } + asset.sidecarFiles)
    }

    private func fileSize(_ name: String) -> String {
        let url = store.fileURL(asset, name)
        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
           let size = attrs[.size] as? NSNumber {
            return ByteCountFormatter.string(fromByteCount: size.int64Value, countStyle: .file)
        }
        return "—"
    }

    private func collectAll() -> [Any] {
        var items: [Any] = []
        for name in fileNames {
            let url = store.fileURL(asset, name)
            if FileManager.default.fileExists(atPath: url.path) { items.append(url) }
        }
        return items
    }
}
