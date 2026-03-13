import SwiftUI
import AVFoundation
import CoreVideo

struct MainView: View {
    @EnvironmentObject private var session: UserSession

    @StateObject private var camera = CameraSession()

    @State private var scanState:    ScanState    = .searching
    @State private var result:       ParkingResult? = nil
    @State private var errorMessage: String?       = nil
    @State private var showProfile   = false

    private let lockFramesNeeded = 12

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if camera.permissionGranted {
                // Camera preview
                CameraPreviewView(session: camera.captureSession)
                    .ignoresSafeArea()

                if result == nil && errorMessage == nil {
                    // Scan overlay
                    ScanOverlayView(state: scanState)
                        .ignoresSafeArea()

                    // Top bar
                    VStack {
                        HStack {
                            Text("ParkSense")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.white)
                            Spacer()
                            Button {
                                showProfile = true
                            } label: {
                                Image(systemName: "person.circle")
                                    .font(.title3)
                                    .foregroundColor(.white)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                        Spacer()
                    }
                }

                // Result card
                if let result {
                    VerdictCard(result: result) { resetToScan() }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                // Error card
                if let errorMessage {
                    VerdictCard(
                        result: ParkingResult(
                            canPark: false,
                            message: "Could not reach the server.\n\n• Check your WiFi\n• Server is running\n\n\(errorMessage)",
                            notes: [],
                            signs: []
                        )
                    ) { resetToScan() }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

            } else {
                // Permission denied
                VStack(spacing: 16) {
                    Text("📷").font(.system(size: 56))
                    Text("Camera access required")
                        .font(.title3.bold()).foregroundColor(.white)
                    Text("Please allow camera access in Settings.")
                        .foregroundColor(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    .foregroundColor(Color(hex: "4CAF50"))
                }
                .padding(32)
            }
        }
        .sheet(isPresented: $showProfile) {
            NavigationStack { ProfileView().environmentObject(session) }
        }
        .onAppear { setupCamera() }
        .onDisappear { camera.stop() }
    }

    // MARK: Setup

    private func setupCamera() {
        camera.requestPermissionAndStart()

        camera.onFrameResult = { hasSign in
            guard result == nil, errorMessage == nil else { return }
            if hasSign {
                camera.lockFrameCount += 1
                if camera.lockFrameCount == 4 {
                    buzz()
                    withAnimation { scanState = .locked }
                } else if camera.lockFrameCount >= lockFramesNeeded {
                    captureAndAnalyse()
                }
            } else {
                camera.lockFrameCount = 0
                if scanState != .searching {
                    withAnimation { scanState = .searching }
                }
            }
        }

        camera.onPhotoCaptured = { pixelBuffer in
            buzz()
            withAnimation { scanState = .analysing }
            sendToServer(pixelBuffer)
        }
    }

    // MARK: Capture

    private func captureAndAnalyse() {
        guard scanState != .analysing else { return }
        camera.setAnalysing(true)
        camera.capturePhoto()
    }

    private func sendToServer(_ pixelBuffer: CVPixelBuffer) {
        // Crop centre region matching the reticle (31% x, 12.5% y, 38% w, 45% h)
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let fullW   = CGFloat(CVPixelBufferGetWidth(pixelBuffer))
        let fullH   = CGFloat(CVPixelBufferGetHeight(pixelBuffer))
        let cropRect = CGRect(
            x: fullW * 0.31, y: fullH * 0.125,
            width: fullW * 0.38, height: fullH * 0.45
        )
        let cropped = ciImage.cropped(to: cropRect)
            .transformed(by: CGAffineTransform(translationX: -cropRect.minX, y: -cropRect.minY))

        let ctx = CIContext()
        guard let cgImage = ctx.createCGImage(cropped, from: cropped.extent) else {
            showError("Image processing failed"); return
        }
        let image = UIImage(cgImage: cgImage)

        let now  = Date()
        let cal  = Calendar.current
        let weekday = cal.component(.weekday, from: now)
        let dayName = ["Sunday","Monday","Tuesday","Wednesday","Thursday","Friday","Saturday"][weekday - 1]
        let hour    = cal.component(.hour, from: now)
        let minute  = cal.component(.minute, from: now)
        let timeStr = String(format: "%02d:%02d", hour, minute)

        Task {
            do {
                let r = try await ApiClient.shared.analyze(image: image, dayName: dayName, timeStr: timeStr)
                await MainActor.run {
                    camera.setAnalysing(false)
                    withAnimation { self.result = r }
                }
            } catch {
                await MainActor.run { showError(error.localizedDescription) }
            }
        }
    }

    // MARK: Reset / Error

    private func resetToScan() {
        camera.setAnalysing(false)
        camera.lockFrameCount = 0
        withAnimation {
            result       = nil
            errorMessage = nil
            scanState    = .searching
        }
    }

    private func showError(_ msg: String) {
        camera.setAnalysing(false)
        withAnimation { errorMessage = msg }
    }

    // MARK: Haptics

    private func buzz() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
}
