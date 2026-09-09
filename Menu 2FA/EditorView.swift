//
//  EditorView.swift
//  Menu 2FA
//

import AppKit
import SwiftUI

struct EditorView: View {
    @Environment(LaunchItemStore.self) private var store
    @State private var session: ItemEditorSession?
    @State private var draggingID: UUID?
    @State private var pointerY: CGFloat = 0
    @State private var grabOffsetY: CGFloat = 0
    @State private var rowFrames: [UUID: CGRect] = [:]

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
            VStack(spacing: 0) {
                ForEach(Array(store.items.enumerated()), id: \.element.id) { index, item in
                    EditorItemRow(
                        item: item,
                        showsDivider: index < store.items.count - 1,
                        onEdit: { session = .edit(item) },
                        onRemove: { store.remove(item) },
                        onReorder: { beginOrUpdateDrag(item: item, value: $0) },
                        onReorderEnd: endDrag
                    )
                    .opacity(draggingID == item.id ? 0 : 1)
                    .background {
                        GeometryReader { geo in
                            Color.clear.preference(
                                key: RowFrameKey.self,
                                value: [item.id: geo.frame(in: .named("settingsList"))]
                            )
                        }
                    }
                }
            }
            .padding(.vertical, 4)
            .coordinateSpace(name: "settingsList")
            .onPreferenceChange(RowFrameKey.self) { rowFrames = $0 }
            .overlay(alignment: .topLeading) {
                dragPreview
            }
        }
    }

    @ViewBuilder
    private var dragPreview: some View {
        if let draggingID,
           let item = store.items.first(where: { $0.id == draggingID }) {
            EditorItemRow(
                item: item,
                showsDivider: false,
                onEdit: {},
                onRemove: {},
                isPreview: true
            )
            .background(.windowBackground)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .shadow(color: .black.opacity(0.18), radius: 8, y: 2)
            .offset(y: pointerY - grabOffsetY)
            .allowsHitTesting(false)
        }
    }

    private func beginOrUpdateDrag(item: LaunchItem, value: DragGesture.Value) {
        if draggingID != item.id {
            draggingID = item.id
            if let frame = rowFrames[item.id] {
                grabOffsetY = value.location.y - frame.minY
            } else {
                grabOffsetY = 0
            }
        }
        pointerY = value.location.y
        moveIfNeeded(dragging: item.id, pointerY: value.location.y)
    }

    private func endDrag() {
        draggingID = nil
        grabOffsetY = 0
        pointerY = 0
    }

    private func moveIfNeeded(dragging: UUID, pointerY: CGFloat) {
        guard store.items.contains(where: { $0.id == dragging }) else { return }

        guard let onto = store.items.first(where: { candidate in
            guard candidate.id != dragging, let frame = rowFrames[candidate.id] else { return false }
            return pointerY >= frame.minY && pointerY < frame.maxY
        }) else { return }

        store.move(id: dragging, onto: onto.id)
    }
}

private struct RowFrameKey: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]

    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

private struct EditorItemRow: View {
    let item: LaunchItem
    let showsDivider: Bool
    let onEdit: () -> Void
    let onRemove: () -> Void
    var onReorder: ((DragGesture.Value) -> Void)?
    var onReorderEnd: (() -> Void)?
    var isPreview = false

    private let iconSize: CGFloat = 32

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
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
                }
                .contentShape(Rectangle())
                .gesture(isPreview ? nil : reorderGesture)

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
                .disabled(isPreview)
                .help("More")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .contentShape(Rectangle())

            if showsDivider {
                Divider()
                    .padding(.leading, 56)
            }
        }
    }

    private var reorderGesture: some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .named("settingsList"))
            .onChanged { value in
                onReorder?(value)
            }
            .onEnded { _ in
                onReorderEnd?()
            }
    }
}

#Preview {
    EditorView()
        .environment(LaunchItemStore.shared)
        .frame(width: 440, height: 540)
}
