//
//  ItemEditorView.swift
//  Menu 2FA
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum ItemEditorSession: Identifiable {
    case add
    case edit(LaunchItem)

    var id: String {
        switch self {
        case .add: return "add"
        case .edit(let item): return item.id.uuidString
        }
    }
}

struct ItemEditorView: View {
    @Environment(\.dismiss) private var dismiss

    let session: ItemEditorSession
    let onSave: (LaunchItem) -> Void

    @State private var name: String
    @State private var secret: String
    @State private var iconData: Data?
    @State private var emoji: String
    @State private var iconURL: String
    @State private var urlIconData: Data?
    @State private var isDropTargeted = false
    @State private var isFetchingIcon = false
    @State private var iconFetchFailed = false
    @State private var iconFetchTask: Task<Void, Never>?
    @State private var iconFetchGeneration = 0
    @State private var isCameraScannerPresented = false
    @State private var isCapturingScreen = false
    @State private var qrImportError: String?

    init(session: ItemEditorSession, onSave: @escaping (LaunchItem) -> Void) {
        self.session = session
        self.onSave = onSave

        switch session {
        case .add:
            _name = State(initialValue: "")
            _secret = State(initialValue: "")
            _iconData = State(initialValue: nil)
            _emoji = State(initialValue: "")
            _iconURL = State(initialValue: "")
            _urlIconData = State(initialValue: nil)
        case .edit(let item):
            _name = State(initialValue: item.name)
            _secret = State(initialValue: item.secret)
            _iconData = State(initialValue: item.iconData)
            _emoji = State(initialValue: item.displayEmoji ?? "")
            _iconURL = State(initialValue: item.url ?? "")
            _urlIconData = State(initialValue: item.urlIconData)
        }
    }

    private var isNew: Bool {
        if case .add = session { return true }
        return false
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && TOTP.isValidSecret(secret)
    }

    private var previewItem: LaunchItem {
        LaunchItem(
            name: name.isEmpty ? " " : name,
            secret: "JBSWY3DPEHPK3PXP",
            iconData: iconData,
            emoji: emoji,
            url: iconURL,
            urlIconData: urlIconData
        )
    }

    private var hasCustomOverride: Bool {
        iconData != nil || !emoji.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(isNew ? "Add Item" : "Edit")
                .font(.headline)

            HStack(alignment: .center, spacing: 14) {
                iconPreview
                    .onDrop(of: [.image, .fileURL], isTargeted: $isDropTargeted, perform: handleDrop)

                HStack(spacing: 8) {
                    Button("Image", action: chooseIcon)
                    EmojiIconButton {
                        applyPickedEmoji($0)
                    }
                    .fixedSize()

                    if hasCustomOverride {
                        Button("Remove") {
                            iconData = nil
                            emoji = ""
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("URL")
                TextField("https://example.com", text: $iconURL)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: iconURL) { _, newValue in
                        scheduleIconFetch(from: newValue)
                    }
                if isFetchingIcon {
                    Text("Fetching icon…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if iconFetchFailed {
                    Text("Couldn’t load an icon from that URL.")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Title")
                TextField("Title", text: $name)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Token")
                HStack(spacing: 8) {
                    TextField("", text: $secret)
                        .textFieldStyle(.roundedBorder)
                        .font(.body.monospaced())

                    Menu {
                        Button {
                            isCameraScannerPresented = true
                        } label: {
                            Label("Camera", systemImage: "camera")
                        }

                        Button {
                            importQRCodeImage()
                        } label: {
                            Label("Choose Image", systemImage: "photo")
                        }

                        Button {
                            captureScreenForQRCode()
                        } label: {
                            Label("Select Screen Area", systemImage: "viewfinder")
                        }
                    } label: {
                        if isCapturingScreen {
                            ProgressView()
                                .controlSize(.small)
                                .frame(width: 18, height: 18)
                        } else {
                            Image(systemName: "qrcode.viewfinder")
                                .frame(width: 18, height: 18)
                        }
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .help("Scan QR Code")
                    .disabled(isCapturingScreen)
                }
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    iconFetchTask?.cancel()
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button(isNew ? "Add" : "Save") {
                    save()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
            }
        }
        .padding(20)
        .frame(width: 400)
        .onChange(of: secret) { _, newValue in
            applySuggestedTitleIfNeeded(from: newValue)
        }
        .onDisappear {
            iconFetchTask?.cancel()
        }
        .sheet(isPresented: $isCameraScannerPresented) {
            QRCameraScannerView(onValue: applyQRCodeValue)
        }
        .alert(
            "Couldn’t Import QR Code",
            isPresented: Binding(
                get: { qrImportError != nil },
                set: { if !$0 { qrImportError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(qrImportError ?? "")
        }
    }

    @ViewBuilder
    private var iconPreview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.quaternary.opacity(0.28))

            Image(nsImage: previewItem.displayIcon(size: 64))
                .resizable()
                .interpolation(.high)
                .scaledToFill()

            if isFetchingIcon && !hasCustomOverride {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .frame(width: 64, height: 64)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(isDropTargeted ? Color.accentColor : .clear, lineWidth: 2)
        }
    }

    private func applyPickedEmoji(_ picked: String) {
        emoji = picked
        iconData = nil
    }

    private func applySuggestedTitleIfNeeded(from raw: String) {
        guard name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if let title = TOTP.fields(from: raw).title {
            name = title
        }
    }

    private func importQRCodeImage() {
        guard let value = QRCodeImporter.chooseImage() else {
            qrImportError = String(localized: "No QR code was found in that image.")
            return
        }
        applyQRCodeValue(value)
    }

    private func captureScreenForQRCode() {
        isCapturingScreen = true
        QRScreenRegionPicker.begin { result in
            isCapturingScreen = false
            switch result {
            case .success(let value):
                applyQRCodeValue(value)
            case .failure(let error):
                qrImportError = error.localizedDescription
            case nil:
                break
            }
        }
    }

    private func applyQRCodeValue(_ rawValue: String) {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard TOTP.isSupportedQRCodePayload(value) else {
            qrImportError = String(localized: "The QR code does not contain a supported TOTP token.")
            return
        }
        let parsed = TOTP.fields(from: value)
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let title = parsed.title {
            name = title
        }
        secret = parsed.secret
    }

    private func scheduleIconFetch(from raw: String) {
        iconFetchTask?.cancel()
        iconFetchFailed = false

        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, IconURLFetcher.normalizedURL(from: trimmed) != nil else {
            isFetchingIcon = false
            iconFetchFailed = false
            urlIconData = nil
            return
        }

        iconFetchGeneration += 1
        let generation = iconFetchGeneration
        isFetchingIcon = true

        iconFetchTask = Task {
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled, generation == iconFetchGeneration else { return }

            let data = await IconURLFetcher.fetchIcon(from: trimmed)
            guard !Task.isCancelled, generation == iconFetchGeneration else { return }

            await MainActor.run {
                isFetchingIcon = false
                if let data {
                    urlIconData = data
                    iconFetchFailed = false
                } else {
                    urlIconData = nil
                    iconFetchFailed = true
                }
            }
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        if let provider = providers.first(where: { $0.canLoadObject(ofClass: NSImage.self) }) {
            _ = provider.loadObject(ofClass: NSImage.self) { object, _ in
                guard let image = object as? NSImage else { return }
                applyDroppedImage(image)
            }
            return true
        }

        if let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }) {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                let url: URL?
                if let value = item as? URL {
                    url = value
                } else if let data = item as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                } else {
                    url = nil
                }
                guard let url else { return }
                let started = url.startAccessingSecurityScopedResource()
                defer {
                    if started {
                        url.stopAccessingSecurityScopedResource()
                    }
                }
                guard let image = NSImage(contentsOf: url) else { return }
                applyDroppedImage(image)
            }
            return true
        }

        return false
    }

    private func applyDroppedImage(_ image: NSImage) {
        let data = Self.pngData(from: Self.resized(image, to: 256))
        DispatchQueue.main.async {
            iconData = data
            emoji = ""
        }
    }

    private func chooseIcon() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.png, .jpeg, .webP, .tiff, .gif, .icns, .image]
        panel.prompt = String(localized: "Add")
        panel.title = String(localized: "Choose Image")

        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let started = url.startAccessingSecurityScopedResource()
        defer {
            if started {
                url.stopAccessingSecurityScopedResource()
            }
        }

        guard let image = NSImage(contentsOf: url) else { return }
        iconData = Self.pngData(from: Self.resized(image, to: 256))
        emoji = ""
    }

    private func save() {
        iconFetchTask?.cancel()
        let parsed = TOTP.fields(from: secret)
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, TOTP.isValidSecret(parsed.secret) else { return }

        let id: UUID
        if case .edit(let item) = session {
            id = item.id
        } else {
            id = UUID()
        }

        onSave(
            LaunchItem(
                id: id,
                name: trimmedName,
                secret: parsed.secret,
                iconData: iconData,
                emoji: emoji,
                url: iconURL,
                urlIconData: urlIconData
            )
        )
        dismiss()
    }

    private static func resized(_ image: NSImage, to maxEdge: CGFloat) -> NSImage {
        let longest = max(image.size.width, image.size.height)
        guard longest > maxEdge, longest > 0 else { return image }

        let scale = maxEdge / longest
        let size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
        let output = NSImage(size: size)
        output.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: NSRect(origin: .zero, size: size))
        output.unlockFocus()
        return output
    }

    private static func pngData(from image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else {
            return nil
        }
        return rep.representation(using: .png, properties: [:])
    }
}

private struct EmojiIconButton: NSViewRepresentable {
    var onPick: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick)
    }

    func makeNSView(context: Context) -> EmojiIconNSButton {
        let button = EmojiIconNSButton()
        button.coordinator = context.coordinator
        return button
    }

    func updateNSView(_ button: EmojiIconNSButton, context: Context) {
        context.coordinator.onPick = onPick
        button.coordinator = context.coordinator
    }

    final class Coordinator {
        var onPick: (String) -> Void
        init(onPick: @escaping (String) -> Void) {
            self.onPick = onPick
        }
    }
}

private final class EmojiIconNSButton: NSButton {
    var coordinator: EmojiIconButton.Coordinator?
    private let sink = EmojiInputSink()

    init() {
        super.init(frame: .zero)
        bezelStyle = .rounded
        setButtonType(.momentaryPushIn)
        title = String(localized: "Emoji")
        target = self
        action = #selector(openPalette)
        sink.isHidden = true
        sink.frame = NSRect(x: 0, y: 0, width: 1, height: 1)
        addSubview(sink)
        sink.onInsert = { [weak self] value in
            self?.coordinator?.onPick(value)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        let size = super.intrinsicContentSize
        return NSSize(width: max(size.width, 72), height: size.height)
    }

    @objc
    private func openPalette() {
        window?.endEditing(for: nil)
        window?.makeFirstResponder(sink)
        NSApp.orderFrontCharacterPalette(sink)
    }
}

private final class EmojiInputSink: NSTextView {
    var onInsert: ((String) -> Void)?

    override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
        super.init(frame: frameRect, textContainer: container)
        isEditable = true
        isSelectable = true
        isRichText = false
        drawsBackground = false
    }

    convenience init() {
        self.init(frame: NSRect(x: 0, y: 0, width: 1, height: 1), textContainer: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }

    override func insertText(_ insertString: Any, replacementRange: NSRange) {
        let raw: String
        if let string = insertString as? String {
            raw = string
        } else if let attributed = insertString as? NSAttributedString {
            raw = attributed.string
        } else {
            return
        }
        string = ""
        if let emoji = LaunchItem.normalizedEmoji(raw) {
            onInsert?(emoji)
        }
    }
}
