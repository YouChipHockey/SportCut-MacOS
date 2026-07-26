//
//  CollectionGroupClipboard.swift
//  Youchip-Stat
//
//  Buffer for copying a tag/label group (with its contents) between collections.
//

import Foundation
import Combine

/// Holds a group copied from one collection so it can be pasted into another.
///
/// Each collection editor owns its own `CustomCollectionManager`, so the buffer has to
/// live outside of it: the user copies in one collection, closes it, opens another and
/// pastes there.
final class CollectionGroupClipboard: ObservableObject {

    static let shared = CollectionGroupClipboard()

    enum Item {
        case tagGroup(group: TagGroup, tags: [Tag])
        case labelGroup(group: LabelGroupData, labels: [Label])
    }

    @Published private(set) var item: Item?

    private init() {}

    func copy(tagGroup: TagGroup, tags: [Tag]) {
        item = .tagGroup(group: tagGroup, tags: tags)
    }

    func copy(labelGroup: LabelGroupData, labels: [Label]) {
        item = .labelGroup(group: labelGroup, labels: labels)
    }

    func clear() {
        item = nil
    }

    /// Non-nil only when the buffer holds a tag group.
    var tagGroupPayload: (group: TagGroup, tags: [Tag])? {
        if case let .tagGroup(group, tags) = item { return (group, tags) }
        return nil
    }

    /// Non-nil only when the buffer holds a label group.
    var labelGroupPayload: (group: LabelGroupData, labels: [Label])? {
        if case let .labelGroup(group, labels) = item { return (group, labels) }
        return nil
    }
}
