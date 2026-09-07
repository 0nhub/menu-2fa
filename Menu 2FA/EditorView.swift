//
//  EditorView.swift
//  Menu 2FA
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct EditorView: View {
    @Environment(LaunchItemStore.self) private var store
    @State private var session: ItemEditorSession?
    @State private var draggingID: LaunchItem.ID?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Group {
                if store.items.isEmpty {
                    emptyState
                } else {
                    itemList
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.quaternary.opacity(0.28), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .padding(16)
        .frame(minWidth: 380, minHeight: 280)
        .background(.windowBackground)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    NSApp.terminate(nil)
                } label: {
                    Image(systemName: "power")
                }
                .help("Quit")

                Button {
                    session = .add
                } label: {
                    Image(systemName: "plus")
                }
                .help("Add Item")
            }
        }
        .sheet(item: $session) { session in
            ItemEditorView(session: session) { item in
                switch session {
                case .add:
                    store.add(item)
                case .edit:
                    store.update(item)
                }
            }
            .presentationSizing(.fitted)
        }
    }

    private var emptyState: some View {
        Button("Add Item") {
            session = .add
        }
        .buttonStyle(.borderedProminent)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var itemList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(store.items.enumerated()), id: \.element.id) { index, item in
                    EditorItemRow(
                        item: item,
                        isDragging: draggingID == item.id,
                        onEdit: { session = .edit(item) },
                        onRemove: { store.remove(item) },
                        onDrag: {
                            draggingID = item.id
                            return NSItemProvider(object: item.id.uuidString as NSString)
                        }
                    )
                    .onDrop(
                        of: [.text],
                        delegate: AccountReorderDropDelegate(
                            itemID: item.id,
                            store: store,
                            draggingID: $draggingID
                        )
                    )

                    if index < store.items.count - 1 {
                        Divider()
                            .padding(.leading, 56)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }
}

private struct EditorItemRow: View {
    let item: LaunchItem
    let isDragging: Bool
    let onEdit: () -> Void
    let onRemove: () -> Void
    let onDrag: () -> NSItemProvider

    private let iconSize: CGFloat = 32

    var body: some View {
        ZStack {
            // macOS `.onDrag` only starts from Image views — fill the row with one.
            Image(nsImage: Self.dragSurface)
                .resizable()
                .interpolation(.none)
                .opacity(0.001)
                .onDrag(onDrag)

            HStack(spacing: 12) {
                Image(nsImage: item.displayIcon(size: iconSize))
                    .resizable()
                    .interpolation(.high)
                    .frame(width: iconSize, height: iconSize)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .allowsHitTesting(false)

                Text(item.name)
                    .font(.body)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .allowsHitTesting(false)

                Menu {
                    Button("Edit", action: onEdit)
                    Button("Delete", role: .destructive, action: onRemove)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 22, height: 22)
                        .background(.quaternary, in: Circle())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .help("More")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
        }
        .frame(maxWidth: .infinity)
        .help("Drag to Reorder")
        .opacity(isDragging ? 0.45 : 1)
        .animation(.snappy(duration: 0.18), value: isDragging)
    }

    private static let dragSurface: NSImage = {
        let image = NSImage(size: NSSize(width: 1, height: 1))
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: 1, height: 1).fill()
        image.unlockFocus()
        image.isTemplate = true
        return image
    }()
}

private struct AccountReorderDropDelegate: DropDelegate {
    let itemID: LaunchItem.ID
    let store: LaunchItemStore
    @Binding var draggingID: LaunchItem.ID?

    func performDrop(info: DropInfo) -> Bool {
        draggingID = nil
        return true
    }

    func dropEntered(info: DropInfo) {
        guard let draggingID, draggingID != itemID else { return }
        withAnimation(.snappy(duration: 0.18)) {
            store.move(id: draggingID, onto: itemID)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }
}

#Preview {
    EditorView()
        .environment(LaunchItemStore.shared)
        .frame(width: 440, height: 540)
}
