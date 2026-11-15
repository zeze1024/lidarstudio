import Foundation
import SwiftUI

enum ScanKind: String, Codable, CaseIterable {
    case room, object, mesh

    var title: String {
        switch self {
        case .room: return "空间"
        case .object: return "物体"
        case .mesh: return "精网"
        }
    }

    var symbol: String {
        switch self {
        case .room: return "square.split.bottomrightquarter"
        case .object: return "cube.transparent"
        case .mesh: return "hexagon"
        }
    }

    var tint: Color {
        switch self {
        case .room: return Theme.accent
        case .object: return Theme.warm
        case .mesh: return Color(red: 0.62, green: 0.72, blue: 1.0)
        }
    }
}

struct ScanAsset: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var kind: ScanKind
    var createdAt: Date
    var modelFile: String?
    var sidecarFiles: [String]
    var summaryLines: [String]
    var stats: String
}

final class ScanStore: ObservableObject {
    @Published private(set) var scans: [ScanAsset] = []

    let root: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        root = docs.appendingPathComponent("Scans", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
        reload()
    }

    func folder(for id: UUID) -> URL {
        root.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    func fileURL(_ asset: ScanAsset, _ name: String) -> URL {
        folder(for: asset.id).appendingPathComponent(name)
    }

    func makeFolder(for kind: ScanKind, name: String) -> (asset: ScanAsset, folder: URL) {
        let asset = ScanAsset(
            id: UUID(),
            name: name,
            kind: kind,
            createdAt: Date(),
            modelFile: nil,
            sidecarFiles: [],
            summaryLines: [],
            stats: ""
        )
        let url = folder(for: asset.id)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return (asset, url)
    }

    func save(_ asset: ScanAsset) {
        let dir = folder(for: asset.id)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let data = try? encoder.encode(asset) {
            try? data.write(to: dir.appendingPathComponent("meta.json"), options: .atomic)
        }
        reload()
    }

    func delete(_ asset: ScanAsset) {
        try? FileManager.default.removeItem(at: folder(for: asset.id))
        reload()
    }

    func reload() {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else {
            scans = []
            return
        }
        var loaded: [ScanAsset] = []
        for dir in entries {
            let meta = dir.appendingPathComponent("meta.json")
            guard let data = try? Data(contentsOf: meta),
                  let asset = try? decoder.decode(ScanAsset.self, from: data) else { continue }
            loaded.append(asset)
        }
        scans = loaded.sorted { $0.createdAt > $1.createdAt }
    }

    /// 体积可读文本，例如 "12.4 MB"
    func sizeText(for asset: ScanAsset) -> String {
        let dir = folder(for: asset.id)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        var total: Int64 = 0
        for name in names {
            let p = dir.appendingPathComponent(name).path
            if let attrs = try? FileManager.default.attributesOfItem(atPath: p),
               let size = attrs[.size] as? NSNumber {
                total += size.int64Value
            }
        }
        return ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
    }
}

enum ScanNaming {
    static func stamp(_ prefix: String) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "MM-dd HH:mm"
        return "\(prefix) \(f.string(from: Date()))"
    }
}
