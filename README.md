# LiDAR Studio

用 iPhone 的激光雷达在本机做高精度三维建模的私人 App。三个模式，全部走 Apple 原生框架，不联网、不上传、不订阅。

| 模式 | 引擎 | 输出 | 精度定位 |
| --- | --- | --- | --- |
| 空间扫描 | RoomPlan | `room.usdz` + 尺寸报告 | 墙/门/窗/家具参数化，厘米级尺寸 |
| 物体重建 | PhotogrammetrySession（本机 Object Capture） | 带贴图 `object.usdz` | 亚厘米级细节 |
| 精网扫描 | ARKit 场景重建 + 逐帧深度融合 | `mesh.obj` + `cloud.ply` | 8 mm 体素稠密点云 |

## 为什么能完全不花钱

- 编译：GitHub Actions 的 macOS 跑机器对公开仓库免费，不需要你有 Mac。
- 安装：Windows 上用 Sideloadly + 免费 Apple ID 签名（免费开发者签名）。
- 唯一代价：免费签名 7 天过期，到期用同一个 IPA 重装一次；同时最多 2 个自签 App。

## 构建

推送到 `main`（或手动触发 `Build IPA` 工作流）会自动：

1. `xcodegen` 生成 Xcode 工程
2. `xcodebuild` 以未签名方式编出 Release `.app`
3. 打包成 `LiDARStudio.ipa`
4. 上传 Actions Artifact，并在 Releases 生成一个可直接下载的公开包
5. 失败时把编译日志写到 `ci/last-build.log` 并提交，方便定位

## 在 Windows 上装进 iPhone

1. 打开仓库 Releases，下载最新的 `LiDARStudio.ipa`。
2. Windows 装 [iTunes](https://www.apple.com/itunes/)（Microsoft Store 版即可，只为装 Apple 驱动）。
3. 装 [Sideloadly](https://sideloadly.io/)（免费）。
4. iPhone 插线连电脑，手机上选「信任此电脑」。
5. Sideloadly：IPA 选刚下载的包，Apple ID 填自己的免费账号，点 Start。
   - 会弹密码 / 双重认证，按提示输入。
   - 首次安装后，iPhone 设置 → 通用 → VPN与设备管理 → 信任该开发者证书。
   - 若提示需要开发者模式（iOS 16+）：设置 → 隐私与安全性 → 开发者模式 → 打开 → 重启。

### 7 天到期怎么办

- 手动：用同一个 IPA 在 Sideloadly 再点一次 Start（20 秒）。
- 自动（推荐）：装 [SideStore](https://sidestore.io/)，配合 Windows 上的 AltServer 后台续签，不用每周插线。

## 三个模式怎么用

### 空间扫描
举到胸口高度横向匀速走，让提示框覆盖每面墙；扫完点「结束扫描」，RoomPlan 参数化建模几秒完成。结果给墙面数、周长、地面面积、平均层高、家具件数与单件尺寸（cm）。「AR 预览」可把模型摆回真实地面；「导出」拿 `room.usdz`。

### 物体重建
物体放纹理丰富、不反光的台面，占画面 60% 以上。同一高度绕满一圈，再升 / 降各来一圈，顶部单独一圈。建议 ≥ 80 张，全精度重建 2–8 分钟（手机上算，注意别过热降频）。输出带贴图 `object.usdz`。

### 精网扫描
慢速移动手机，青色网格是 ARKit 实时重建表面；HUD 的「稠密点」是 LiDAR 深度图逐帧反投影 + 8 mm 体素去重的点云。结束导出：

- `mesh.obj`：三角网格（世界坐标），进 Blender / MeshLab 直接用
- `cloud.ply`：带 RGB 点云，CloudCompare / MeshLab / Windows 3D 查看器都能开

## 把模型拿到 Windows

- iPhone「文件」App → 我的 iPhone → LiDAR Studio（已开文件共享）→ 选文件 → 分享到 iCloud / 邮件 / 微信给自己
- App 内「分享 / 导出」→ 存到「文件」或直接传到 Windows
- Windows 打开：`.usdz` 用「3D 查看器」，`.obj` 用 Blender，`.ply` 用 CloudCompare

## 目录结构

```
project.yml                     # xcodegen 工程规格（.xcodeproj 由它生成，不入库）
Sources/App/                    # App 入口
Sources/Core/                   # 数据模型、OBJ/PLY 导出器、设备能力探测
Sources/Room/                   # RoomPlan 空间扫描
Sources/Object/                 # 照片采集 + 本机摄影测量
Sources/Mesh/                   # ARKit 网格 + 稠密点云融合
Sources/UI/                     # 首页、扫描库、预览、分享
.github/workflows/build.yml     # 免费云编译流水线
```

## 已知边界

- 物体重建需要 LiDAR + A14 及以上 + iOS 18+（iPhone 12 Pro 及之后的 Pro 机型、iPad Pro）
- 免费签名 7 天有效，同时最多 2 个自签 App
- 精网扫描在 A16 上稳定约 300 万点（8 mm 体素），再细意义不大
- 强反光、纯黑无纹理、透明物体会明显掉质量——这是算法物理限制
