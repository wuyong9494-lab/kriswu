import AVFoundation
import PhotosUI
import SwiftUI
import UIKit

/// Continuous multi-shot camera & batch review view for 「数传计划 → 拍照识别」.
/// - Stays inside the capture session after each shot (NEVER auto-OCRs after 1 photo).
/// - Displays `"已拍 N 张"` counter and scrollable filmstrip with preview, delete, and retake.
/// - Tapping `"完成"` delivers all captured photos in exact capture order for batch recognition.
struct PassPlanBurstCameraView: View {
    var onFinish: ([UIImage]) -> Void
    @Environment(\.dismiss) private var dismiss

    @StateObject private var controller = BurstCameraController()
    @State private var capturedPhotos: [CapturedShot] = []
    @State private var previewingShot: CapturedShot? = nil
    @State private var retakingIndex: Int? = nil
    @State private var albumSelections: [PhotosPickerItem] = []
    @State private var shutterFlash = false

    struct CapturedShot: Identifiable {
        let id = UUID()
        var image: UIImage
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if controller.isCameraAvailable {
                BurstCameraPreviewLayer(session: controller.session)
                    .ignoresSafeArea()
                    .opacity(shutterFlash ? 0.35 : 1.0)
                    .animation(.easeOut(duration: 0.14), value: shutterFlash)
            } else {
                cameraUnavailablePlaceholder
            }

            VStack(spacing: 0) {
                topBar
                Spacer()
                bottomDock
            }
        }
        .statusBarHidden(true)
        .onAppear {
            controller.start()
        }
        .onDisappear {
            controller.stop()
        }
        .onChange(of: albumSelections) { items in
            guard !items.isEmpty else { return }
            let picked = items
            albumSelections = []
            Task { @MainActor in
                for item in picked {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let img = UIImage(data: data) {
                        appendOrReplace(img)
                    }
                }
            }
        }
        .fullScreenCover(item: $previewingShot) { shot in
            shotPreviewModal(shot)
        }
    }

    private var topBar: some View {
        VStack(spacing: 8) {
            HStack {
                Button("取消") {
                    dismiss()
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Color.black.opacity(0.55), in: Capsule())
                .accessibilityIdentifier("passplan.burst.cancel")

                Spacer()

                HStack(spacing: 6) {
                    Circle()
                        .fill(capturedPhotos.isEmpty ? Color.white.opacity(0.5) : Color.green)
                        .frame(width: 7, height: 7)
                    Text("已拍 \(capturedPhotos.count) 张")
                        .font(.subheadline.weight(.bold).monospacedDigit())
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Color.black.opacity(0.65), in: Capsule())
                .accessibilityIdentifier("passplan.burst.count")

                Spacer()

                Button {
                    controller.toggleFlash()
                } label: {
                    Image(systemName: controller.flashOn ? "bolt.fill" : "bolt.slash")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(controller.flashOn ? .yellow : .white)
                        .frame(width: 36, height: 36)
                        .background(Color.black.opacity(0.55), in: Circle())
                }
                .disabled(!controller.isCameraAvailable)
            }

            Text(
                retakingIndex != nil
                ? "正在重拍第 \((retakingIndex ?? 0) + 1) 张 · 拍完自动替换该张"
                : (capturedPhotos.isEmpty
                   ? "第 1 张请拍清表头（网页表 / 导出表格）；可连拍多张，最后点「完成」统一识别"
                   : "向下翻页继续拍数据行（自动沿用第 1 张表头）；拍齐后点右下角「完成」")
            )
            .font(.caption.weight(.medium))
            .foregroundStyle(.white.opacity(0.92))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(Color.black.opacity(0.52), in: Capsule())
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    private var bottomDock: some View {
        VStack(spacing: 12) {
            if !capturedPhotos.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(Array(capturedPhotos.enumerated()), id: \.element.id) { idx, shot in
                            ZStack(alignment: .topTrailing) {
                                Button {
                                    previewingShot = shot
                                } label: {
                                    ZStack(alignment: .bottomLeading) {
                                        Image(uiImage: shot.image)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 64, height: 82)
                                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                    .strokeBorder(
                                                        retakingIndex == idx ? Color.yellow : Color.white.opacity(0.6),
                                                        lineWidth: retakingIndex == idx ? 2.5 : 1
                                                    )
                                            )
                                        Text("#\(idx + 1)")
                                            .font(.system(size: 10, weight: .bold).monospacedDigit())
                                            .foregroundStyle(.white)
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 2)
                                            .background(Color.black.opacity(0.70), in: Capsule())
                                            .padding(4)
                                    }
                                }
                                .buttonStyle(.plain)

                                Button {
                                    withAnimation(.snappy(duration: 0.2)) {
                                        if retakingIndex == idx { retakingIndex = nil }
                                        capturedPhotos.removeAll { $0.id == shot.id }
                                    }
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 18))
                                        .foregroundStyle(.white, Color.black.opacity(0.75))
                                }
                                .offset(x: 6, y: -6)
                                .accessibilityLabel("删除第 \(idx + 1) 张")
                            }
                            .padding(.top, 6)
                            .padding(.trailing, 4)
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .frame(height: 92)
            }

            HStack(alignment: .center) {
                PhotosPicker(
                    selection: $albumSelections,
                    maxSelectionCount: 12,
                    matching: .images
                ) {
                    VStack(spacing: 4) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.title3)
                        Text("相册连选")
                            .font(.caption2.weight(.semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(width: 72, height: 52)
                    .background(Color.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }

                Spacer()

                Button {
                    triggerShutter()
                } label: {
                    ZStack {
                        Circle()
                            .strokeBorder(.white, lineWidth: 4)
                            .frame(width: 74, height: 74)
                        Circle()
                            .fill(controller.isCapturing ? Color.gray : Color.white)
                            .frame(width: 60, height: 60)
                    }
                }
                .disabled(!controller.isCameraAvailable || controller.isCapturing)
                .accessibilityLabel("拍摄一张")
                .accessibilityIdentifier("passplan.burst.shutter")

                Spacer()

                Button {
                    let ordered = capturedPhotos.map(\.image)
                    guard !ordered.isEmpty else { return }
                    dismiss()
                    onFinish(ordered)
                } label: {
                    VStack(spacing: 2) {
                        Text("完成")
                            .font(.subheadline.weight(.bold))
                        Text(capturedPhotos.isEmpty ? "待拍" : "识别 \(capturedPhotos.count) 张")
                            .font(.caption2.weight(.semibold).monospacedDigit())
                    }
                    .foregroundStyle(capturedPhotos.isEmpty ? Color.white.opacity(0.45) : Color.white)
                    .frame(width: 82, height: 52)
                    .background(
                        capturedPhotos.isEmpty ? Color.white.opacity(0.12) : Color.blue,
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                    )
                }
                .disabled(capturedPhotos.isEmpty)
                .accessibilityIdentifier("passplan.burst.done")
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 18)
        }
        .padding(.top, 10)
        .background(
            LinearGradient(
                colors: [Color.black.opacity(0.0), Color.black.opacity(0.86)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .bottom)
        )
    }

    private var cameraUnavailablePlaceholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 46))
                .foregroundStyle(.white.opacity(0.75))
            Text(controller.unavailableMessage ?? "当前设备无可用后置相机")
                .font(.headline)
                .foregroundStyle(.white)
            Text("可点左下角「相册连选」按顺序添加多张数传计划图，再点右下角「完成」统一识别与智能去重。")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.75))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)
        }
    }

    private func shotPreviewModal(_ shot: CapturedShot) -> some View {
        let idx = capturedPhotos.firstIndex(where: { $0.id == shot.id })
        return ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 12) {
                HStack {
                    Button("关闭") { previewingShot = nil }
                        .foregroundStyle(.white)
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(idx.map { "第 \($0 + 1) / \(capturedPhotos.count) 张" } ?? "预览")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                    Spacer()
                    Button("删除", role: .destructive) {
                        capturedPhotos.removeAll { $0.id == shot.id }
                        previewingShot = nil
                    }
                    .font(.subheadline.weight(.semibold))
                }
                .padding(.horizontal, 18)
                .padding(.top, 12)

                Spacer()
                Image(uiImage: shot.image)
                    .resizable()
                    .scaledToFit()
                    .padding(.horizontal, 8)
                Spacer()

                HStack(spacing: 14) {
                    if let idx {
                        Button {
                            retakingIndex = idx
                            previewingShot = nil
                        } label: {
                            Label("重拍这张", systemImage: "camera.rotate")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .foregroundStyle(.white)
                        }
                    }
                    Button {
                        previewingShot = nil
                    } label: {
                        Text("保留并返回连拍")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.blue, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .foregroundStyle(.white)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 20)
            }
        }
    }

    private func triggerShutter() {
        shutterFlash = true
        Haptics.tap()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) { shutterFlash = false }
        controller.capturePhoto { image in
            guard let image else { return }
            appendOrReplace(image)
        }
    }

    private func appendOrReplace(_ image: UIImage) {
        if let idx = retakingIndex, capturedPhotos.indices.contains(idx) {
            capturedPhotos[idx] = CapturedShot(image: image)
            retakingIndex = nil
        } else {
            capturedPhotos.append(CapturedShot(image: image))
        }
    }
}

/// Serial-queue-owned AVCaptureSession wrapper for strict Swift 6 concurrency safety (zero warnings).
private final class BurstCaptureSessionBox: @unchecked Sendable {
    let session = AVCaptureSession()
    let photoOutput = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label: "wumind.passplan.burstCamera")
    private var configured = false

    func configureAndStart(completion: @escaping @Sendable (Bool, String?) -> Void) {
        queue.async { [self] in
            if configured {
                if !session.isRunning { session.startRunning() }
                completion(true, nil)
                return
            }
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                  let input = try? AVCaptureDeviceInput(device: device) else {
                completion(false, "无法打开后置摄像头")
                return
            }
            session.beginConfiguration()
            session.sessionPreset = .photo
            if session.canAddInput(input) { session.addInput(input) }
            if session.canAddOutput(photoOutput) { session.addOutput(photoOutput) }
            session.commitConfiguration()
            configured = true
            session.startRunning()
            completion(true, nil)
        }
    }

    func stop() {
        queue.async { [self] in
            if session.isRunning {
                session.stopRunning()
            }
        }
    }

    func capture(flashOn: Bool, delegate: AVCapturePhotoCaptureDelegate) {
        let settings = AVCapturePhotoSettings()
        if photoOutput.supportedFlashModes.contains(flashOn ? .on : .off) {
            settings.flashMode = flashOn ? .on : .off
        }
        photoOutput.capturePhoto(with: settings, delegate: delegate)
    }
}

@MainActor
private final class BurstCameraController: NSObject, ObservableObject {
    @Published var isCameraAvailable = false
    @Published var isCapturing = false
    @Published var flashOn = false
    @Published var unavailableMessage: String? = nil

    private let box = BurstCaptureSessionBox()
    var session: AVCaptureSession { box.session }
    private var onCaptureCompletion: ((UIImage?) -> Void)?

    func start() {
        #if targetEnvironment(simulator)
        isCameraAvailable = false
        unavailableMessage = "模拟器无实体相机，请使用「相册连选」测试多张连续识别"
        return
        #else
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            startBox()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                Task { @MainActor [weak self] in
                    if granted {
                        self?.startBox()
                    } else {
                        self?.isCameraAvailable = false
                        self?.unavailableMessage = "尚未开启相机权限，请在系统设置中允许访问相机"
                    }
                }
            }
        default:
            isCameraAvailable = false
            unavailableMessage = "相机权限已关闭，请在系统设置中开启或使用「相册连选」"
        }
        #endif
    }

    private func startBox() {
        box.configureAndStart { [weak self] ok, err in
            Task { @MainActor [weak self] in
                self?.isCameraAvailable = ok
                self?.unavailableMessage = err
            }
        }
    }

    func stop() {
        box.stop()
    }

    func toggleFlash() {
        flashOn.toggle()
    }

    func capturePhoto(completion: @escaping (UIImage?) -> Void) {
        guard isCameraAvailable, !isCapturing else { return }
        isCapturing = true
        onCaptureCompletion = completion
        box.capture(flashOn: flashOn, delegate: self)
    }
}

extension BurstCameraController: @preconcurrency AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let data = photo.fileDataRepresentation()
        Task { @MainActor [weak self] in
            self?.isCapturing = false
            let cb = self?.onCaptureCompletion
            self?.onCaptureCompletion = nil
            cb?(data.flatMap(UIImage.init(data:)))
        }
    }
}

private struct BurstCameraPreviewLayer: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewContainerView {
        let view = PreviewContainerView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewContainerView, context: Context) {
        if uiView.previewLayer.session !== session {
            uiView.previewLayer.session = session
        }
    }

    final class PreviewContainerView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}
