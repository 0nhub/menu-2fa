//
//  EditorView.swift
//  Menu 2FA
//

import AppKit
import SwiftUI

struct EditorView: View {
    @Environment(LaunchItemStore.self) private var store
    @State private var session: ItemEditorSession?

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
                        canMoveUp: index > 0,
                        canMoveDown: index < store.items.count - 1,
                        onMoveUp: { store.moveUp(item) },
                        onMoveDown: { store.moveDown(item) },
                        onEdit: { session = .edit(item) },
                        onRemove: { store.remove(item) }
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
    let canMoveUp: Bool
    let canMoveDown: Bool
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onEdit: () -> Void
    let onRemove: () -> Void

    private let iconSize: CGFloat = 32

    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: item.displayIcon(size: iconSize))
                .resizable()
                .interpolation(.high)
                .frame(width: iconSize, height: iconSize)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            Text(item.name)
                .font(.body)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            ControlGroup {
                Button(action: onMoveUp) {
                    Image(systemName: "chevron.up")
                }
                .disabled(!canMoveUp)
                .help("Move Up")

                Button(action: onMoveDown) {
                    Image(systemName: "chevron.down")
                }
                .disabled(!canMoveDown)
                .help("Move Down")
            }
            .controlSize(.small)

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
}

#Preview {
    EditorView()
        .environment(LaunchItemStore.shared)
        .frame(width: 440, height: 540)
}
