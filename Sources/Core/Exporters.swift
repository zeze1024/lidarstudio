import Foundation
import ARKit
import RealityKit
import simd

enum MeshExporter {
    private static func fmt(_ v: Float) -> String {
        String(format: "%.4f", v)
    }

    /// 把所有 ARMeshAnchor 合并成一个世界坐标系的 OBJ。
    static func writeOBJ(anchors: [ARMeshAnchor], to url: URL) throws {
        var body = "# LiDAR Studio mesh export\n# vertices: world space\n"
        body.reserveCapacity(1 << 20)
        var indexBase = 1

        for anchor in anchors {
            let geo = anchor.geometry
            let transform = anchor.transform
            let vertexCount = geo.vertices.count
            let vertexBuffer = geo.vertices.buffer.contents().advanced(by: geo.vertices.offset)
            let stride = geo.vertices.stride

            for i in 0..<vertexCount {
                let f = vertexBuffer.advanced(by: i * stride).assumingMemoryBound(to: Float.self)
                let p = transform * SIMD4<Float>(f[0], f[1], f[2], 1)
                body += "v \(fmt(p.x)) \(fmt(p.y)) \(fmt(p.z))\n"
            }

            let faceCount = geo.faces.count
            let faceBuffer = geo.faces.buffer.contents()
            if geo.faces.bytesPerIndex == 4 {
                let idx = faceBuffer.assumingMemoryBound(to: UInt32.self)
                var i = 0
                while i + 2 < faceCount {
                    body += "f \(Int(idx[i]) + indexBase) \(Int(idx[i + 1]) + indexBase) \(Int(idx[i + 2]) + indexBase)\n"
                    i += 3
                }
            } else {
                let idx = faceBuffer.assumingMemoryBound(to: UInt16.self)
                var i = 0
                while i + 2 < faceCount {
                    body += "f \(Int(idx[i]) + indexBase) \(Int(idx[i + 1]) + indexBase) \(Int(idx[i + 2]) + indexBase)\n"
                    i += 3
                }
            }

            indexBase += vertexCount
        }

        try body.write(to: url, atomically: true, encoding: .utf8)
    }
}

enum PointCloudExporter {
    /// 写 ASCII PLY（带 RGB），CloudCompare / MeshLab / Windows 3D 查看器都能直接打开。
    static func write(points: [SIMD3<Float>], colors: [SIMD3<UInt8>], to url: URL) throws {
        var header = """
        ply
        format ascii 1.0
        comment LiDAR Studio fused point cloud
        element vertex \(points.count)
        property float x
        property float y
        property float z

        """
        if colors.count == points.count, !colors.isEmpty {
            header += "property uchar red\nproperty uchar green\nproperty uchar blue\n"
        }
        header += "end_header\n"

        FileManager.default.createFile(atPath: url.path, contents: nil)
        let handle = try FileHandle(forWritingTo: url)
        handle.write(Data(header.utf8))

        guard points.count == colors.count else {
            var buffer = ""
            for p in points {
                buffer += "\(String(format: "%.4f", p.x)) \(String(format: "%.4f", p.y)) \(String(format: "%.4f", p.z))\n"
                if buffer.utf8.count > 2_000_000 {
                    handle.write(Data(buffer.utf8))
                    buffer.removeAll(keepingCapacity: true)
                }
            }
            handle.write(Data(buffer.utf8))
            try handle.close()
            return
        }

        var buffer = ""
        buffer.reserveCapacity(1 << 20)
        for i in points.indices {
            let p = points[i]
            let c = colors[i]
            buffer += "\(String(format: "%.4f", p.x)) \(String(format: "%.4f", p.y)) \(String(format: "%.4f", p.z)) \(c.x) \(c.y) \(c.z)\n"
            if buffer.utf8.count > 2_000_000 {
                handle.write(Data(buffer.utf8))
                buffer.removeAll(keepingCapacity: true)
            }
        }
        handle.write(Data(buffer.utf8))
        try handle.close()
    }
}

enum DeviceSupport {
    static var hasLiDAR: Bool {
        ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth)
    }

    static var supportsMeshReconstruction: Bool {
        ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification)
    }

    static var supportsPhotogrammetry: Bool {
        PhotogrammetrySession.isSupported
    }

    static var hasSceneDepth: Bool {
        ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth)
    }

    static var machineText: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let mirror = Mirror(reflecting: systemInfo.machine)
        let identifier = mirror.children.reduce(into: "") { partial, element in
            guard let value = element.value as? Int8, value != 0 else { return }
            partial += String(UnicodeScalar(UInt8(value)))
        }
        return identifier
    }
}
