//
//  QRCodeImport.swift
//  Menu 2FA
//

import AppKit
@preconcurrency import AVFoundation
import Combine
import ScreenCaptureKit
import SwiftUI
import Vision

enum QRImportFailure: LocalizedError {
    case noDisplay
    case noQRCode
    case unsupportedToken

    var errorDescription: String? {
        switch self {
        case .noDisplay:
            String(localized: "No display could be captured.")
        case .noQRCode:
            String(localized: "No QR code was found in the selected area.")
        case .unsupportedToken:
            String(localized: "The QR code does not contain a supported TOTP token.")
        }
    }
}

enum QRCodeImporter {
    static func value(from image: NSImage) -> String? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        return value(from: cgImage)
    }

    static func value(from cgImage: CGImage) -> String? {
        let request = VNDetectBarcodesRequest()
        request.symbologies = [.qr]

        do {
            try VNImageRequestHandler(cgImage: cgImage).perform([request])
            return request.results?.first?.payloadStringValue
        } catch {
            return nil
        }
    }

    @MainActor
    static func chooseImage() -> String? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.png, .jpeg, .webP, .tiff, .gif, .heic, .image]
        panel.prompt = String(localized: "Scan")
        panel.title = String(localized: "Choose QR Code Image")

        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return nil }

        let started = url.startAccessingSecurityScopedResource()
        defer {
            if started {
                url.stopAccessingSecurityScopedResource()
            }
        }
        guard let image = NSImage(contentsOf: url) else { return nil }
        return value(from: image)
    }

    static func captureDisplays() async throws -> [CapturedDisplay] {
        let content = try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: true
        )

        var captures: [CapturedDisplay] = []
        for display in content.displays {
            let filter = SCContentFilter(display: display, excludingWindows: [])
            let configuration = SCStreamConfiguration()
            configuration.width = display.width
            configuration.height = display.height
            configuration.showsCursor = false
            configuration.capturesAudio = false

            let image = try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: configuration
            )
            captures.append(
                CapturedDisplay(
                    id: display.displayID,
                    frame: display.frame,
                    image: image
                )
            )
        }
        return captures
    }
}

struct CapturedDisplay: Identifiable {
    let id: CGDirectDisplayID
    let frame: CGRect
    let image: CGImage
}

@MainActor
final class QRScreenRegionPicker {
    private static var activePicker: QRScreenRegionPicker?

    private var captures: [CGDirectDisplayID: CapturedDisplay] = [:]
    private var overlayWindows: [NSWindow] = []
    private var hiddenWindows: [NSWindow] = []
    private var escapeMonitor: Any?
    private var completion: ((Result<String, Error>?) -> Void)?

    static func begin(completion: @escaping (Result<String, Error>?) -> Void) {
        guard activePicker == nil else { return }
        let picker = QRScreenRegionPicker()
        activePicker = picker
        picker.completion = completion
        picker.start()
    }

    private func start() {
        hiddenWindows = NSApp.windows.filter(\.isVisible)
        hiddenWindows.forEach { $0.orderOut(nil) }

        Task {
            try? await Task.sleep(for: .milliseconds(250))
            do {
                let capturedDisplays = try await QRCodeImporter.captureDisplays()
                guard !capturedDisplays.isEmpty else {
                    throw QRImportFailure.noDisplay
                }
                captures = Dictionary(
                    uniqueKeysWithValues: capturedDisplays.map { ($0.id, $0) }
                )
                showOverlays()
            } catch {
                finish(.failure(error))
            }
        }
    }

    private func showOverlays() {
        for screen in NSScreen.screens {
            guard let displayID = screen.displayID, captures[displayID] != nil else { continue }

            let overlay = QRSelectionOverlayView(frame: CGRect(origin: .zero, size: screen.frame.size))
            overlay.onSelection = { [weak self] rect in
                self?.selected(rect: rect, on: displayID)
            }
            overlay.onCancel = { [weak self] in
                self?.cancel()
            }

            let window = NSWindow(
                contentRect: screen.frame,
                styleMask: .borderless,
                backing: .buffered,
                defer: false,
                screen: screen
            )
            window.backgroundColor = .clear
            window.isOpaque = false
            window.hasShadow = false
            window.level = .screenSaver
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.isReleasedWhenClosed = false
            window.contentView = overlay
            window.setFrame(screen.frame, display: false)
            window.orderFrontRegardless()
            overlayWindows.append(window)
        }

        guard let keyWindow = overlayWindows.first,
              let overlay = keyWindow.contentView
        else {
            finish(.failure(QRImportFailure.noDisplay))
            return
        }
        NSApp.activate(ignoringOtherApps: true)
        keyWindow.makeKeyAndOrderFront(nil)
        keyWindow.makeFirstResponder(overlay)

        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                self?.cancel()
                return nil
            }
            return event
        }
    }

    private func selected(rect: CGRect, on displayID: CGDirectDisplayID) {
        guard let capture = captures[displayID],
              let window = overlayWindows.first(where: { $0.screen?.displayID == displayID })
        else {
            finish(.failure(QRImportFailure.noDisplay))
            return
        }

        let bounds = window.contentView?.bounds ?? .zero
        let scaleX = CGFloat(capture.image.width) / bounds.width
        let scaleY = CGFloat(capture.image.height) / bounds.height
        let pixelRect = CGRect(
            x: rect.minX * scaleX,
            y: (bounds.height - rect.maxY) * scaleY,
            width: rect.width * scaleX,
            height: rect.height * scaleY
        ).integral

        guard let cropped = capture.image.cropping(to: pixelRect),
              let value = QRCodeImporter.value(from: cropped)
        else {
            finish(.failure(QRImportFailure.noQRCode))
            return
        }
        guard TOTP.isSupportedQRCodePayload(value) else {
            finish(.failure(QRImportFailure.unsupportedToken))
            return
        }
        finish(.success(value))
    }

    private func cancel() {
        finish(nil)
    }

    private func finish(_ result: Result<String, Error>?) {
        if let escapeMonitor {
            NSEvent.removeMonitor(escapeMonitor)
            self.escapeMonitor = nil
        }
        overlayWindows.forEach { $0.close() }
        overlayWindows.removeAll()

        for window in hiddenWindows {
            window.makeKeyAndOrderFront(nil)
        }
        hiddenWindows.removeAll()
        NSApp.activate(ignoringOtherApps: true)

        let completion = completion
        self.completion = nil
        Self.activePicker = nil
        completion?(result)
    }
}

private final class QRSelectionOverlayView: NSView {
    var onSelection: ((CGRect) -> Void)?
    var onCancel: (() -> Void)?

    private var startPoint: CGPoint?
    private var currentPoint: CGPoint?

    override var acceptsFirstResponder: Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func mouseDown(with event: NSEvent) {
        startPoint = convert(event.locationInWindow, from: nil)
        currentPoint = startPoint
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        currentPoint = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        currentPoint = convert(event.locationInWindow, from: nil)
        guard let selectionRect, selectionRect.width >= 8, selectionRect.height >= 8 else {
            startPoint = nil
            currentPoint = nil
            needsDisplay = true
            return
        }
        onSelection?(selectionRect)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onCancel?()
        } else {
            super.keyDown(with: event)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.16).setFill()
        bounds.fill()

        guard let selectionRect else { return }
        NSColor.clear.setFill()
        selectionRect.fill(using: .copy)
        NSColor.white.setStroke()
        let outline = NSBezierPath(rect: selectionRect.insetBy(dx: 1, dy: 1))
        outline.lineWidth = 2
        outline.stroke()
    }

    private var selectionRect: CGRect? {
        guard let startPoint, let currentPoint else { return nil }
        return CGRect(
            x: min(startPoint.x, currentPoint.x),
            y: min(startPoint.y, currentPoint.y),
            width: abs(currentPoint.x - startPoint.x),
            height: abs(currentPoint.y - startPoint.y)
        ).intersection(bounds)
    }
}

private extension NSScreen {
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?
            .uint32Value
    }
}

struct QRCameraScannerView: View {
    let onValue: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var scanner = QRCameraScanner()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Scan QR Code")
                .font(.headline)

            ZStack {
                CameraPreview(session: scanner.session)

                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.9), lineWidth: 2)
                    .frame(width: 230, height: 230)
                    .shadow(radius: 2)
            }
            .frame(width: 520, height: 360)
            .background(.black)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            Text(scanner.status)
                .font(.caption)
                .foregroundStyle(scanner.failed ? Color.red : Color.secondary)

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding(18)
        .onAppear {
            scanner.onValue = { value in
                onValue(value)
                dismiss()
            }
            scanner.start()
        }
        .onDisappear {
            scanner.stop()
        }
    }
}

@MainActor
private final class QRCameraScanner: NSObject, ObservableObject, AVCaptureMetadataOutputObjectsDelegate {
    let session = AVCaptureSession()

    @Published var status = String(localized: "Point the camera at a QR code.")
    @Published var failed = false
    var onValue: ((String) -> Void)?

    private let sessionQueue = DispatchQueue(label: "ga.sgroi.menu-2fa.camera")
    private var configured = false
    private var deliveredValue = false

    func start() {
        Task {
            let allowed: Bool
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized:
                allowed = true
            case .notDetermined:
                allowed = await AVCaptureDevice.requestAccess(for: .video)
            default:
                allowed = false
            }

            guard allowed else {
                failed = true
                status = String(localized: "Camera access is disabled in System Settings.")
                return
            }

            configureAndStart()
        }
    }

    func stop() {
        sessionQueue.async { [session] in
            if session.isRunning {
                session.stopRunning()
            }
        }
    }

    private func configureAndStart() {
        guard !configured else {
            sessionQueue.async { [session] in
                if !session.isRunning {
                    session.startRunning()
                }
            }
            return
        }

        guard let device = AVCaptureDevice.default(for: .video) else {
            failed = true
            status = String(localized: "No camera is available.")
            return
        }

        do {
            let input = try AVCaptureDeviceInput(device: device)
            let output = AVCaptureMetadataOutput()

            guard session.canAddInput(input), session.canAddOutput(output) else {
                failed = true
                status = String(localized: "The camera could not be started.")
                return
            }

            session.beginConfiguration()
            session.sessionPreset = .high
            session.addInput(input)
            session.addOutput(output)
            output.setMetadataObjectsDelegate(self, queue: .main)
            output.metadataObjectTypes = [.qr]
            session.commitConfiguration()
            configured = true

            sessionQueue.async { [session] in
                session.startRunning()
            }
        } catch {
            failed = true
            status = error.localizedDescription
        }
    }

    nonisolated func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard let value = metadataObjects
            .compactMap({ ($0 as? AVMetadataMachineReadableCodeObject)?.stringValue })
            .first
        else { return }

        Task { @MainActor [weak self] in
            guard let self, !deliveredValue else { return }
            guard TOTP.isSupportedQRCodePayload(value) else {
                failed = true
                status = String(localized: "This QR code does not contain a supported TOTP token.")
                return
            }
            deliveredValue = true
            onValue?(value)
        }
    }
}

private struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> CameraPreviewView {
        let view = CameraPreviewView()
        view.previewLayer.session = session
        return view
    }

    func updateNSView(_ view: CameraPreviewView, context: Context) {
        view.previewLayer.session = session
    }
}

private final class CameraPreviewView: NSView {
    let previewLayer = AVCaptureVideoPreviewLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        previewLayer.videoGravity = .resizeAspectFill
        layer?.addSublayer(previewLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        previewLayer.frame = bounds
    }
}
