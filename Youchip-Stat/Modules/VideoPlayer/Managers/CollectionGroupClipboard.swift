//
//  CollectionGroupClipboard.swift
//  Youchip-Stat
//
//  Buffer for copying tag/label groups (with their contents) between collections.
//

import Foundation
import Combine

/// Holds groups copied from one collection so they can be pasted into another.
///
/// Each collection editor owns its own `CustomCollectionManager`, so the buffer has to
/// live outside of it: the user copies in one collection, closes it, opens another and
/// pastes there. Поддерживает копирование нескольких групп одновременно.
final class CollectionGroupClipboard: ObservableObject {

    static let shared = CollectionGroupClipboard()

    struct TagGroupItem { let group: TagGroup; let tags: [Tag] }
    struct LabelGroupItem { let group: LabelGroupData; let labels: [Label] }

    /// Скопированные группы тегов (несколько сразу). Буфер держит либо теги, либо лейблы.
    @Published private(set) var tagGroups: [TagGroupItem] = []
    @Published private(set) var labelGroups: [LabelGroupItem] = []

    private init() {}

    // MARK: - Копирование

    func copy(tagGroup: TagGroup, tags: [Tag]) {
        copy(tagGroups: [(tagGroup, tags)])
    }

    func copy(tagGroups groups: [(group: TagGroup, tags: [Tag])]) {
        self.tagGroups = groups.map { TagGroupItem(group: $0.group, tags: $0.tags) }
        self.labelGroups = []
    }

    func copy(labelGroup: LabelGroupData, labels: [Label]) {
        copy(labelGroups: [(labelGroup, labels)])
    }

    func copy(labelGroups groups: [(group: LabelGroupData, labels: [Label])]) {
        self.labelGroups = groups.map { LabelGroupItem(group: $0.group, labels: $0.labels) }
        self.tagGroups = []
    }

    func clear() {
        tagGroups = []
        labelGroups = []
    }

    // MARK: - Состояние (для UI/подсветки)

    var hasTagGroups: Bool { !tagGroups.isEmpty }
    var hasLabelGroups: Bool { !labelGroups.isEmpty }

    /// Id скопированных групп тегов — для подсветки в редакторе.
    var copiedTagGroupIDs: Set<String> { Set(tagGroups.map { $0.group.id }) }
    /// Id скопированных групп лейблов — для подсветки в редакторе.
    var copiedLabelGroupIDs: Set<String> { Set(labelGroups.map { $0.group.id }) }
}
