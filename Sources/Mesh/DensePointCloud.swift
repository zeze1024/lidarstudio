import Foundation
import simd

/// 体素去重的稠密点云：LiDAR 每帧深度图反投影后灌进来，1cm 体素内只保留一个点。
final class DensePointCloud {
    private(set) var points: [SIMD3<Float>] = []
    private(set) var colors: [SIMD3<UInt8>] = []

    let voxelSize: Float
    let maxPoints: Int
    private var keys: Set<Int64> = []

    private let bias: Int64 = 1 << 20

    init(voxelSize: Float = 0.01, maxPoints: Int = 3_500_000) {
        self.voxelSize = voxelSize
        self.maxPoints = maxPoints
        points.reserveCapacity(64_000)
        colors.reserveCapacity(64_000)
    }

    var count: Int { points.count }
    var isFull: Bool { points.count >= maxPoints }

    /// 返回 true 表示这个点被采纳（新体素）。
    @discardableResult
    func add(_ position: SIMD3<Float>, color: SIMD3<UInt8>) -> Bool {
        guard !isFull else { return false }
        guard position.x.isFinite, position.y.isFinite, position.z.isFinite else { return false }

        let vx = Int32((position.x / voxelSize).rounded())
        let vy = Int32((position.y / voxelSize).rounded())
        let vz = Int32((position.z / voxelSize).rounded())
        guard abs(vx) < (1 << 20), abs(vy) < (1 << 20), abs(vz) < (1 << 20) else { return false }

        let key = ((Int64(vx) + bias) << 42) | ((Int64(vy) + bias) << 21) | (Int64(vz) + bias)
        if keys.contains(key) { return false }
        keys.insert(key)
        points.append(position)
        colors.append(color)
        return true
    }

    func reset() {
        points.removeAll(keepingCapacity: true)
        colors.removeAll(keepingCapacity: true)
        keys.removeAll(keepingCapacity: true)
    }
}
