//
//  StandardCollectionViewerView.swift
//  Youchip-Stat
//
//  Просмотр стандартной (встроенной) коллекции только для чтения.
//  Редактировать нельзя — можно лишь выбрать группы тегов/лейблов и продублировать их
//  в свою коллекцию, либо создать полную копию стандартной коллекции.
//

import SwiftUI

struct StandardCollectionViewerView: View {

    let collectionName: String
    @Binding var isPresented: Bool
    /// Создать редактируемую копию всей стандартной коллекции.
    var onCreateCopy: () -> Void

    @State private var selectedTagGroupIDs: Set<String> = []
    @State private var selectedLabelGroupIDs: Set<String> = []

    private var standard: StandardCollection? {
        TagLibraryManager.shared.standardCollections.first(where: { $0.name == collectionName })
    }

    private var duplicationTargets: [CollectionInfo] {
        CollectionsBookmarksManager.shared.loadCollections()
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if let standard = standard {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        tagGroupsSection(standard)
                        labelGroupsSection(standard)
                    }
                    .padding(20)
                }
            } else {
                Spacer()
                Text(collectionName)
                    .foregroundColor(.secondary)
                Spacer()
            }

            Divider()
            footer
        }
        .frame(minWidth: 560, minHeight: 480)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "folder.fill")
                .foregroundColor(.blue)
                .font(.system(size: 20))
            VStack(alignment: .leading, spacing: 2) {
                Text(collectionName)
                    .font(.title3)
                    .fontWeight(.semibold)
                Text(^String.Titles.collectionStandardReadOnly)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Text(^String.Titles.collectionMultiSelectHint)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: - Tag groups

    private func tagGroupsSection(_ standard: StandardCollection) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "tag.fill").foregroundColor(.blue)
                Text(^String.Titles.tagGroups).font(.headline)
                Spacer()
                Text("\(standard.tagGroups.count)")
                    .font(.caption).foregroundColor(.secondary)
            }

            if !selectedTagGroupIDs.isEmpty {
                GroupDuplicationBar(
                    chips: standard.tagGroups
                        .filter { selectedTagGroupIDs.contains($0.id) }
                        .map { GroupDuplicationBar.Chip(id: $0.id, name: $0.name) },
                    targets: duplicationTargets,
                    accent: .blue,
                    onRemoveChip: { selectedTagGroupIDs.remove($0) },
                    onClear: { selectedTagGroupIDs.removeAll() },
                    onDuplicate: { duplicateTagGroups(standard, to: $0) }
                )
            }

            ForEach(standard.tagGroups) { group in
                groupRow(
                    name: group.name,
                    subtitle: "\(tagsForGroup(standard, group).count) \(^String.Titles.tagsInGroup)",
                    isSelected: selectedTagGroupIDs.contains(group.id),
                    accent: .blue,
                    toggle: { toggle(&selectedTagGroupIDs, group.id) }
                )
            }
        }
    }

    // MARK: - Label groups

    private func labelGroupsSection(_ standard: StandardCollection) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "label.fill").foregroundColor(.green)
                Text(^String.Titles.labelGroups).font(.headline)
                Spacer()
                Text("\(standard.labelGroups.count)")
                    .font(.caption).foregroundColor(.secondary)
            }

            if !selectedLabelGroupIDs.isEmpty {
                GroupDuplicationBar(
                    chips: standard.labelGroups
                        .filter { selectedLabelGroupIDs.contains($0.id) }
                        .map { GroupDuplicationBar.Chip(id: $0.id, name: $0.name) },
                    targets: duplicationTargets,
                    accent: .green,
                    onRemoveChip: { selectedLabelGroupIDs.remove($0) },
                    onClear: { selectedLabelGroupIDs.removeAll() },
                    onDuplicate: { duplicateLabelGroups(standard, to: $0) }
                )
            }

            ForEach(standard.labelGroups) { group in
                groupRow(
                    name: group.name,
                    subtitle: "\(labelsForGroup(standard, group).count)",
                    isSelected: selectedLabelGroupIDs.contains(group.id),
                    accent: .green,
                    toggle: { toggle(&selectedLabelGroupIDs, group.id) }
                )
            }
        }
    }

    private func groupRow(name: String, subtitle: String, isSelected: Bool, accent: Color, toggle: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundColor(isSelected ? accent : .secondary)
                .font(.system(size: 16))
            Image(systemName: "folder.fill")
                .foregroundColor(accent)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.headline).foregroundColor(.primary)
                Text(subtitle).font(.caption).foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? accent.opacity(0.15) : Color(NSColor.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? accent.opacity(0.5) : Color(NSColor.separatorColor), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: toggle)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 12) {
            Button(^String.Titles.cancelButtonTitle) {
                isPresented = false
            }
            .keyboardShortcut(.cancelAction)

            Spacer()

            Button {
                onCreateCopy()
                isPresented = false
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus.square.on.square")
                    Text(^String.Titles.collectionCreateCopy)
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: - Helpers

    private func toggle(_ set: inout Set<String>, _ id: String) {
        if set.contains(id) { set.remove(id) } else { set.insert(id) }
    }

    private func tagsForGroup(_ standard: StandardCollection, _ group: TagGroup) -> [Tag] {
        let byID = Dictionary(standard.tags.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return group.tags.compactMap { byID[$0] }
    }

    private func labelsForGroup(_ standard: StandardCollection, _ group: LabelGroupData) -> [Label] {
        let byID = Dictionary(standard.labels.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return group.lables.compactMap { byID[$0] }
    }

    private func duplicateTagGroups(_ standard: StandardCollection, to targetID: String) {
        let payloads = standard.tagGroups
            .filter { selectedTagGroupIDs.contains($0.id) }
            .map { GroupDuplicationService.TagGroupPayload(group: $0, tags: tagsForGroup(standard, $0)) }
        guard !payloads.isEmpty else { return }
        GroupDuplicationService.duplicate(tagGroups: payloads, labelGroups: [], intoCollectionID: targetID)
        selectedTagGroupIDs.removeAll()
    }

    private func duplicateLabelGroups(_ standard: StandardCollection, to targetID: String) {
        let payloads = standard.labelGroups
            .filter { selectedLabelGroupIDs.contains($0.id) }
            .map { GroupDuplicationService.LabelGroupPayload(group: $0, labels: labelsForGroup(standard, $0)) }
        guard !payloads.isEmpty else { return }
        GroupDuplicationService.duplicate(tagGroups: [], labelGroups: payloads, intoCollectionID: targetID)
        selectedLabelGroupIDs.removeAll()
    }
}
