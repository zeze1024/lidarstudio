import SwiftUI
import ARKit
import SceneKit
import CoreImage

class MeshScanner: NSObject, ObservableObject, ARSCNViewDelegate {
    @Published var meshAnchorCount = 0
    @Published var pointCount = 0
    @Published var isRunning = false
    @Published var status = "就绪"
    @Published var lastError: String?

    let sceneView = ARSCNView(frame: .zero)

    private(set) var anchors: [UUID: ARMeshAnchor] = [:]
    let cloud = DensePointCloud(voxelSize: 0.008, maxPoints: 3_500_000)

    private var configured = false
    private var lastDepthTimestamp: TimeInterval = 0
    private let workQueue = DispatchQueue(label: "lidarstudio.mesh.depth")
    private var busy = false

    func configure() {
        guard !configured else { return }
        configured = true
        sceneView.delegate = self
        sceneView.backgroundColor = .black
        sceneView.automaticallyUpdatesLighting = false
        sceneView.antialiasingMode = .multisampling2X
        sceneView.debugOptions = []
    }

    func start() {
        configure()
        var config = ARWorldTrackingConfiguration()
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification) {
            config.sceneReconstruction = .meshWithClassification
        }
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.smoothedSceneDepth) {
            config.frameSemantics.insert(.smoothedSceneDepth)
        } else if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            config.frameSemantics.insert(.sceneDepth)
        }
        config.planeDetection = []
        config.environmentTexturing = .none

        anchors.removeAll()
        cloud.reset()
        meshAnchorCount = 0
        pointCount = 0
        sceneView.session.run(config, options: [.resetTracking, .removeExistingAnchors])
        isRunning = true
        status = "扫描中 · 慢慢移动，把每处表面都覆盖到"
    }

    func stop() {
        sceneView.session.pause()
        isRunning = false
        status = "已结束"
    }

    // MARK: 网格可视化

    func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
        guard let mesh = anchor as? ARMeshAnchor else { return }
        node.addChildNode(makeMeshNode(mesh))
        anchors[mesh.identifier] = mesh
        meshAnchorCount = anchors.count
    }

    func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
        guard let mesh = anchor as? ARMeshAnchor else { return }
        node.childNodes.forEach { $0.removeFromParentNode() }
        node.addChildNode(makeMeshNode(mesh))
        anchors[mesh.identifier] = mesh
    }

    func renderer(_ renderer: SCNSceneRenderer, didRemove node: SCNNode, for anchor: ARAnchor) {
        guard let mesh = anchor as? ARMeshAnchor else { return }
        anchors.removeValue(forKey: mesh.identifier)
        meshAnchorCount = anchors.count
    }

    private func makeMeshNode(_ mesh: ARMeshAnchor) -> SCNNode {
        let geo = mesh.geometry
        let vertices = geo.vertices
        let source = SCNGeometrySource(
            buffer: vertices.buffer,
            vertexFormat: vertices.format,
            semantic: .vertex,
            vertexCount: vertices.count,
            dataOffset: vertices.offset,
            dataStride: vertices.stride
        )
        let element = SCNGeometryElement(
            buffer: geo.faces.buffer,
            primitiveType: .triangles,
            primitiveCount: geo.faces.count / 3,
            bytesPerIndex: geo.faces.bytesPerIndex
        )
        let geometry = SCNGeometry(sources: [source], elements: [element])
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.fillMode = .lines
        material.diffuse.contents = UIColor(red: 0.29, green: 0.90, blue: 0.94, alpha: 1)
        material.transparency = 0.85
        material.isDoubleSided = true
        material.writesToDepthBuffer = false
        geometry.materials = [material]

        let node = SCNNode(geometry: geometry)
        node.transform = SCNMatrix4(mesh.transform)
        node.renderingOrder = 5
        return node
    }

    // MARK: 稠密点云

    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        guard isRunning, !busy else { return }
        guard time - lastDepthTimestamp > 0.15 else { return }
        lastDepthTimestamp = time
        guard let frame = sceneView.session.currentFrame else { return }
        busy = true
        workQueue.async { [weak self, frame] in
            self?.fuseDepth(frame)
            DispatchQueue.main.async { self?.busy = false }
        }
    }

    private func fuseDepth(_ frame: ARFrame) {
        guard !cloud.isFull else { return }
        guard let depthData = frame.smoothedSceneDepth ?? frame.sceneDepth else { return }
        let depthMap = depthData.depthMap
        let confidenceMap = depthData.confidenceMap

        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        if let confidenceMap { CVPixelBufferLockBaseAddress(confidenceMap, .readOnly) }
        defer {
            CVPixelBufferUnlockBaseAddress(depthMap, .readOnly)
            if let confidenceMap { CVPixelBufferUnlockBaseAddress(confidenceMap, .readOnly) }
        }

        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)
        guard let depthBase = CVPixelBufferGetBaseAddress(depthMap) else { return }
        let depthRowBytes = CVPixelBufferGetBytesPerRow(depthMap)
        let confidenceBase = confidenceMap.flatMap { CVPixelBufferGetBaseAddress($0) }
        let confidenceRowBytes = confidenceMap.map { CVPixelBufferGetBytesPerRow($0) } ?? 0

        let intrinsics = frame.camera.intrinsics
        let reference = frame.camera.imageResolution
        let sx = Float(width) / Float(reference.width)
        let sy = Float(height) / Float(reference.height)
        let fx = intrinsics.columns.0.x * sx
        let fy = intrinsics.columns.1.y * sy
        let cx = intrinsics.columns.2.x * sx
        let cy = intrinsics.columns.2.y * sy
        let cameraTransform = frame.camera.transform

        let image = frame.capturedImage
        CVPixelBufferLockBaseAddress(image, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(image, .readOnly) }

        let lumaBase = CVPixelBufferGetBaseAddressOfPlane(image, 0)
        let lumaRowBytes = CVPixelBufferGetBytesPerRowOfPlane(image, 0)
        let chromaBase = CVPixelBufferGetBaseAddressOfPlane(image, 1)
        let chromaRowBytes = chromaBase == nil ? 0 : CVPixelBufferGetBytesPerRowOfPlane(image, 1)
        let imageWidth = CVPixelBufferGetWidth(image)
        let imageHeight = CVPixelBufferGetHeight(image)
        let mapX = Float(imageWidth) / Float(width)
        let mapY = Float(imageHeight) / Float(height)

        guard let lumaPtr = lumaBase else { return }

        var added = 0
        let step = 2
        var v = 0
        while v < height {
            let depthRow = depthBase.advanced(by: v * depthRowBytes).assumingMemoryBound(to: Float32.self)
            var u = 0
            while u < width {
                if let confidenceBase {
                    let confidence = confidenceBase
                        .advanced(by: v * confidenceRowBytes + u)
                        .assumingMemoryBound(to: UInt8.self)
                        .pointee
                    if confidence < 1 {
                        u += step
                        continue
                    }
                }
                let z = depthRow[u]
                if z.isFinite, z > 0.08, z < 5.0 {
                    let camX = (Float(u) - cx) / fx * z
                    let camY = (Float(v) - cy) / fy * z
                    let world4 = cameraTransform * SIMD4<Float>(camX, -camY, -z, 1)
                    let world = SIMD3<Float>(world4.x, world4.y, world4.z)

                    var color = SIMD3<UInt8>(180, 190, 200)
                    var ix = Int(Float(u) * mapX)
                    var iy = Int(Float(v) * mapY)
                    ix = min(max(ix, 0), imageWidth - 1)
                    iy = min(max(iy, 0), imageHeight - 1)
                    let luma = lumaPtr.advanced(by: iy * lumaRowBytes + ix).assumingMemoryBound(to: UInt8.self).pointee
                    if let chromaBase {
                        let offset = (iy / 2) * chromaRowBytes + (ix / 2) * 2
                        let cb = Int(chromaBase.advanced(by: offset).assumingMemoryBound(to: UInt8.self).pointee)
                        let cr = Int(chromaBase.advanced(by: offset + 1).assumingMemoryBound(to: UInt8.self).pointee)
                        let yValue = Float(luma)
                        let r = clampColor(yValue + 1.402 * Float(cr - 128))
                        let g = clampColor(yValue - 0.344136 * Float(cb - 128) - 0.714136 * Float(cr - 128))
                        let b = clampColor(yValue + 1.772 * Float(cb - 128))
                        color = SIMD3<UInt8>(UInt8(r), UInt8(g), UInt8(b))
                    } else {
                        color = SIMD3<UInt8>(luma, luma, luma)
                    }

                    if cloud.add(world, color: color) { added += 1 }
                }
                u += step
            }
            v += step
        }

        if added > 0 {
            let total = cloud.count
            DispatchQueue.main.async { [weak self] in
                self?.pointCount = total
            }
        }
    }

    private func clampColor(_ value: Float) -> Int {
        Int(min(max(value, 0), 255))
    }

    // MARK: 导出

    func export(to folder: URL) throws -> (meshFile: String, cloudFile: String, stats: String) {
        let objURL = folder.appendingPathComponent("mesh.obj")
        let plyURL = folder.appendingPathComponent("cloud.ply")
        let anchorList = Array(anchors.values)
        guard !anchorList.isEmpty || !cloud.points.isEmpty else {
            throw NSError(domain: "LiDARStudio", code: 1, userInfo: [NSLocalizedDescriptionKey: "没有采到几何数据，换个角度多扫一会儿"])
        }
        if !anchorList.isEmpty {
            try MeshExporter.writeOBJ(anchors: anchorList, to: objURL)
        }
        try PointCloudExporter.write(points: cloud.points, colors: cloud.colors, to: plyURL)
        let stats = "网格块 \(anchorList.count) · 点云 \(cloud.count) 点"
        return ("mesh.obj", "cloud.ply", stats)
    }
}

struct ARMeshSurface: UIViewRepresentable {
    let sceneView: ARSCNView

    func makeUIView(context: Context) -> ARSCNView { sceneView }
    func updateUIView(_ uiView: ARSCNView, context: Context) {}
}

struct MeshScanScreen: View {
    @EnvironmentObject private var store: ScanStore
    @Environment(\.dismiss) private var dismiss

    @StateObject private var scanner = MeshScanner()
    @State private var savedAsset: ScanAsset?
    @State private var showShare = false
    @State private var shareItems: [Any] = []
    @State private var errorText: String?

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            ARMeshSurface(sceneView: scanner.sceneView).ignoresSafeArea()

            VStack {
                ScanOverlayTopBar(
                    title: "精网扫描",
                    subtitle: scanner.status,
                    onClose: { scanner.stop(); dismiss() }
                )

                HStack(spacing: 8) {
                    StatChip(label: "网格块", value: "\(scanner.meshAnchorCount)")
                    StatChip(label: "稠密点", value: "\(scanner.pointCount)")
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)

                Spacer()

                if let errorText {
                    Text(errorText)
                        .font(.footnote)
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 18)
                }

                if let asset = savedAsset {
                    HStack(spacing: 10) {
                        Button {
                            shareItems = collectedFiles(for: asset)
                            showShare = true
                        } label: {
                            Label("导出 OBJ / PLY", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(GlassButtonStyle())
                        Button { dismiss() } label: {
                            Label("完成", systemImage: "checkmark").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(GlassButtonStyle(tint: Theme.accent))
                    }
                    .padding(.horizontal, 18)
                } else {
                    HStack(spacing: 12) {
                        if scanner.isRunning {
                            Button {
                                scanner.stop()
                                finish()
                            } label: {
                                Text("结束并导出")
                                    .font(.system(size: 17, weight: .bold))
                                    .foregroundStyle(.black)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 16)
                                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.warm))
                            }
                            .buttonStyle(.plain)
                        } else {
                            Button {
                                errorText = nil
                                scanner.start()
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
            .padding(.bottom, 24)
        }
        .onAppear { scanner.configure() }
        .sheet(isPresented: $showShare) { ShareSheet(items: shareItems) }
    }

    private func finish() {
        let (asset, folder) = store.makeFolder(for: .mesh, name: ScanNaming.stamp("精网"))
        do {
            let result = try scanner.export(to: folder)
            var final = asset
            final.modelFile = result.meshFile
            final.sidecarFiles = [result.cloudFile]
            final.summaryLines = [
                "三角网格：\(result.stats)",
                "点云体素 8 mm，RGB 来自相机逐帧采样",
                "OBJ 可直接进 Blender / MeshLab，PLY 可直接进 CloudCompare"
            ]
            final.stats = result.stats
            store.save(final)
            savedAsset = final
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func collectedFiles(for asset: ScanAsset) -> [Any] {
        var items: [Any] = []
        for name in ([asset.modelFile].compactMap { $0 } + asset.sidecarFiles) {
            let url = store.fileURL(asset, name)
            if FileManager.default.fileExists(atPath: url.path) { items.append(url) }
        }
        return items
    }
}
