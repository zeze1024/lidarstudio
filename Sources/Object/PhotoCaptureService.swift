import SwiftUI
import UIKit
import AVFoundation

final class PhotoCaptureService: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate {
    @Published var capturedCount = 0
    @Published var lastError: String?

    let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label: "lidarstudio.photo")
    private var configured = false
    private(set) var imagesDirectory: URL?
    private var pending = 0

    func configureIfNeeded() {
        guard !configured else { return }
        configured = true

        queue.async { [weak self] in
            guard let self else { return }
            self.session.beginConfiguration()
            self.session.sessionPreset = .photo

            if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
               let input = try? AVCaptureDeviceInput(device: device),
               self.session.canAddInput(input) {
                self.session.addInput(input)
                try? device.lockForConfiguration()
                if device.isFocusModeSupported(.continuousAutoFocus) {
                    device.focusMode = .continuousAutoFocus
                }
                device.unlockForConfiguration()
            }

            guard self.session.canAddOutput(self.photoOutput) else {
                self.session.commitConfiguration()
                DispatchQueue.main.async { self.lastError = "相机输出不可用" }
                return
            }
            self.session.addOutput(self.photoOutput)
            self.photoOutput.isHighResolutionCaptureEnabled = true
            self.session.commitConfiguration()
        }
    }

    func makeDirectory(_ url: URL) {
        imagesDirectory = url
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func start() {
        configureIfNeeded()
        queue.async { [weak self] in
            guard let self else { return }
            if !self.session.isRunning { self.session.startRunning() }
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            if self.session.isRunning { self.session.stopRunning() }
        }
    }

    var canShoot: Bool { capturedCount < 260 }

    func shoot() {
        guard canShoot else { return }
        guard let connection = photoOutput.connection(with: .video) else { return }
        if connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }
        let settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
        settings.isHighResolutionPhotoEnabled = true
        pending += 1
        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        pending = max(0, pending - 1)
        if let error {
            DispatchQueue.main.async { self.lastError = error.localizedDescription }
            return
        }
        guard let data = photo.fileDataRepresentation(), let dir = imagesDirectory else { return }
        let name = String(format: "img_%04d.jpg", capturedCount + 1)
        do {
            try data.write(to: dir.appendingPathComponent(name), options: .atomic)
            DispatchQueue.main.async { self.capturedCount += 1 }
        } catch {
            DispatchQueue.main.async { self.lastError = "写入照片失败：\(error.localizedDescription)" }
        }
    }
}
