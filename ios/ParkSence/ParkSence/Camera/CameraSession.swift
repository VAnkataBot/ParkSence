import AVFoundation
import CoreVideo
import Combine

/// Manages AVCaptureSession, delivers frames to ColorDetector, and reports lock state.
final class CameraSession: NSObject, ObservableObject {

    @Published var permissionGranted = false
    @Published var lockFrameCount    = 0

    let captureSession = AVCaptureSession()

    private let frameQueue  = DispatchQueue(label: "parksense.frames", qos: .userInteractive)
    private let outputQueue = DispatchQueue(label: "parksense.output", qos: .userInteractive)
    private var photoOutput = AVCapturePhotoOutput()
    private var isAnalysing = false

    var onFrameResult: ((Bool) -> Void)?           // called on main thread
    var onPhotoCaptured: ((CVPixelBuffer) -> Void)? // called on main thread

    // MARK: Setup

    func requestPermissionAndStart() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            DispatchQueue.main.async { self.permissionGranted = true }
            startSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async { self.permissionGranted = granted }
                if granted { self.startSession() }
            }
        default:
            DispatchQueue.main.async { self.permissionGranted = false }
        }
    }

    private func startSession() {
        frameQueue.async {
            self.captureSession.beginConfiguration()
            self.captureSession.sessionPreset = .hd1280x720

            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                  let input  = try? AVCaptureDeviceInput(device: device),
                  self.captureSession.canAddInput(input) else {
                self.captureSession.commitConfiguration(); return
            }
            self.captureSession.addInput(input)

            // Frame analysis output
            let videoOutput = AVCaptureVideoDataOutput()
            videoOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
            videoOutput.alwaysDiscardsLateVideoFrames = true
            videoOutput.setSampleBufferDelegate(self, queue: self.outputQueue)
            if self.captureSession.canAddOutput(videoOutput) {
                self.captureSession.addOutput(videoOutput)
            }

            // Photo capture output
            if self.captureSession.canAddOutput(self.photoOutput) {
                self.captureSession.addOutput(self.photoOutput)
            }

            self.captureSession.commitConfiguration()
            self.captureSession.startRunning()
        }
    }

    func stop() {
        frameQueue.async { self.captureSession.stopRunning() }
    }

    // MARK: Photo capture

    func capturePhoto() {
        let settings = AVCapturePhotoSettings()
        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    func setAnalysing(_ value: Bool) {
        isAnalysing = value
    }
}

// MARK: - Frame delegate

extension CameraSession: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard !isAnalysing,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let hasSign = ColorDetector.hasSignInCenter(pixelBuffer)
        DispatchQueue.main.async { self.onFrameResult?(hasSign) }
    }
}

// MARK: - Photo delegate

extension CameraSession: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        guard error == nil,
              let pixelBuffer = photo.pixelBuffer else { return }
        DispatchQueue.main.async { self.onPhotoCaptured?(pixelBuffer) }
    }
}
