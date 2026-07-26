//
//  DartfishXMLProjectImporter.swift
//  Youchip-Stat
//
//  Parses Dartfish `.dartclip` XML (LIBRARY_ITEM tree with Marker.Event children)
//  into a ProjectImportModel with a synthetic custom collection.
//
//  Dartfish stores each event as a nested <LIBRARY_ITEM ItemType="Marker.Event">
//  with IN/OUT times (RefTime = 100ns ticks) and a set of <CATEGORY name="…">value.
//  Mapping (confirmed with product):
//   • category NAME  → tag (a timeline line, e.g. "Moment/Мом", "OZP-DZC/за-зз")
//   • category VALUE → label inside a label group named after the category
//   • the event's main tag is the category whose value matches its Title;
//     the remaining categories are attached as labels.
//   • the ubiquitous "Групповой блок" category stays a normal label.
//

import Foundation

enum DartfishXMLImportError: LocalizedError {
    case noEvents
    case parseFailed

    var errorDescription: String? {
        switch self {
        case .noEvents:
            return ^String.Titles.xmlImportNoInstancesError
        case .parseFailed:
            return ^String.Titles.xmlImportParseFailedError
        }
    }
}

private struct DartfishCategory {
    let name: String
    let value: String
}

private final class DartfishMutableEvent {
    var start: Double = 0
    var end: Double = 0
    var title: String = ""
    var categories: [DartfishCategory] = []
}

private final class DartfishXMLParserDelegate: NSObject, XMLParserDelegate {

    private(set) var rootName: String = ""
    private(set) var events: [DartfishMutableEvent] = []

    private var currentText = ""
    /// Stack of LIBRARY_ITEM markers: true if that item is a Marker.Event.
    private var libraryItemStack: [Bool] = []
    private var currentEvent: DartfishMutableEvent?
    private var currentCategoryName: String?
    private var inTitleProperty = false

    private func refTimeToSeconds(_ raw: String?, unit: String?) -> Double {
        guard let raw, let value = Double(raw) else { return 0 }
        // RefTime is measured in 100-nanosecond ticks.
        if unit == nil || unit == "RefTime" {
            return value / 10_000_000.0
        }
        return value
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        if let s = String(data: CDATABlock, encoding: .utf8) {
            currentText += s
        }
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        currentText = ""
        switch elementName {
        case "LIBRARY_ITEM":
            let isMarker = attributeDict["ItemType"] == "Marker.Event"
            libraryItemStack.append(isMarker)
            if isMarker, currentEvent == nil {
                let event = DartfishMutableEvent()
                event.start = refTimeToSeconds(attributeDict["IN"], unit: attributeDict["UNIT"])
                event.end = refTimeToSeconds(attributeDict["OUT"], unit: attributeDict["UNIT"])
                currentEvent = event
            }
        case "CATEGORY":
            if currentEvent != nil {
                currentCategoryName = attributeDict["name"]
            }
        case "Property":
            if currentEvent != nil, attributeDict["Name"] == "Title" {
                inTitleProperty = true
            }
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let text = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        defer { currentText = "" }

        switch elementName {
        case "LIBRARY_ITEM":
            let wasMarker = libraryItemStack.popLast() ?? false
            if wasMarker, let event = currentEvent {
                if event.end >= event.start, (!event.categories.isEmpty || !event.title.isEmpty) {
                    events.append(event)
                }
                currentEvent = nil
            }
        case "NAME":
            // Root video name: <NAME> at the top level (no active marker).
            if currentEvent == nil, rootName.isEmpty, !text.isEmpty {
                rootName = text
            }
        case "CATEGORY":
            if let event = currentEvent, let name = currentCategoryName {
                let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                if !cleanName.isEmpty, !text.isEmpty {
                    event.categories.append(DartfishCategory(name: cleanName, value: text))
                }
            }
            currentCategoryName = nil
        case "Property":
            if inTitleProperty, let event = currentEvent {
                event.title = text
            }
            inTitleProperty = false
        default:
            break
        }
    }
}

enum DartfishXMLProjectImporter {

    /// Palette used to give imported tag lines distinct colors (Dartfish clips carry no colors).
    private static let tagColorPalette = [
        "4A90D9", "E24A4A", "3FA34D", "E2A03F", "8A5AD9",
        "1FA6A6", "D94A8C", "6B7A8F", "C0663F", "3F6BD9"
    ]

    private static func xmlDataAsUTF8(_ data: Data) -> Data {
        guard data.count >= 2 else { return data }
        if data.count >= 3, data[0] == 0xEF, data[1] == 0xBB, data[2] == 0xBF {
            return Data(data.dropFirst(3))
        }
        if data[0] == 0xFF, data[1] == 0xFE, let s = String(data: data, encoding: .utf16LittleEndian) {
            return Data(stripBOM(s).utf8)
        }
        if data[0] == 0xFE, data[1] == 0xFF, let s = String(data: data, encoding: .utf16BigEndian) {
            return Data(stripBOM(s).utf8)
        }
        if data[0] == 0x3C, data[1] == 0x00, let s = String(data: data, encoding: .utf16LittleEndian) {
            return Data(s.utf8)
        }
        if data[0] == 0x00, data[1] == 0x3C, let s = String(data: data, encoding: .utf16BigEndian) {
            return Data(s.utf8)
        }
        return data
    }

    private static func stripBOM(_ string: String) -> String {
        string.first == "\u{FEFF}" ? String(string.dropFirst()) : string
    }

    /// Drops the trailing " (N)" occurrence counter Dartfish appends to titles.
    private static func titleBase(_ title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let range = trimmed.range(of: #"\s*\(\d+\)\s*$"#, options: .regularExpression) else {
            return trimmed
        }
        return String(trimmed[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func makeProjectImport(from xmlData: Data, fileName: String) throws -> ProjectImportModel {
        let delegate = DartfishXMLParserDelegate()
        let parser = XMLParser(data: xmlDataAsUTF8(xmlData))
        parser.delegate = delegate
        guard parser.parse() else {
            throw DartfishXMLImportError.parseFailed
        }

        let events = delegate.events
        guard !events.isEmpty else {
            throw DartfishXMLImportError.noEvents
        }

        let projectTitle: String = {
            let base = (fileName as NSString).deletingPathExtension
            // `.mp4.dartclip` → strip a trailing media extension too.
            return (base as NSString).pathExtension.isEmpty ? base : (base as NSString).deletingPathExtension
        }()
        let collectionDisplayName = ^String.Titles.xmlImportCollectionDisplayName

        // Resolve the primary category name for each event (its timeline tag).
        func primaryCategoryName(for event: DartfishMutableEvent) -> String? {
            guard !event.categories.isEmpty else {
                let base = titleBase(event.title)
                return base.isEmpty ? nil : base
            }
            let base = titleBase(event.title)
            if !base.isEmpty,
               let match = event.categories.first(where: { $0.value.trimmingCharacters(in: .whitespacesAndNewlines) == base }) {
                return match.name
            }
            return event.categories.first?.name
        }

        // --- Label groups: one per category NAME; labels = distinct values under it ---
        var labelGroupOrder: [String] = []                 // category names, first-seen order
        var labelIdByNameValue: [String: String] = [:]     // "name\u{1}value" -> label id
        var labelsByGroup: [String: [String]] = [:]        // category name -> [label id]
        var labels: [Label] = []

        func labelId(name: String, value: String) -> String {
            let key = "\(name)\u{1}\(value)"
            if let existing = labelIdByNameValue[key] { return existing }
            let lid = UUID().uuidString
            labelIdByNameValue[key] = lid
            labels.append(Label(id: lid, name: value, description: ""))
            if labelsByGroup[name] == nil {
                labelsByGroup[name] = []
                labelGroupOrder.append(name)
            }
            labelsByGroup[name]?.append(lid)
            return lid
        }

        // Pre-register every category so groups/labels are complete regardless of primary choice.
        for event in events {
            for cat in event.categories {
                _ = labelId(name: cat.name, value: cat.value)
            }
        }

        var labelGroups: [LabelGroupData] = []
        var labelGroupIdByName: [String: String] = [:]
        for name in labelGroupOrder {
            let gid = UUID().uuidString
            labelGroupIdByName[name] = gid
            labelGroups.append(LabelGroupData(id: gid, name: name, lables: labelsByGroup[name] ?? []))
        }
        let allLabelGroupIds = labelGroups.map { $0.id }

        // --- Tags: one per unique primary category name ---
        var tagOrder: [String] = []
        var tagByName: [String: Tag] = [:]
        var primaryNameByEventIndex: [Int: String] = [:]

        for (idx, event) in events.enumerated() {
            guard let primary = primaryCategoryName(for: event) else { continue }
            primaryNameByEventIndex[idx] = primary
            if tagByName[primary] == nil {
                let color = tagColorPalette[tagOrder.count % tagColorPalette.count]
                let tag = Tag(
                    id: UUID().uuidString,
                    primaryID: nil,
                    name: primary,
                    description: "",
                    color: color,
                    defaultTimeBefore: 0,
                    defaultTimeAfter: 0,
                    collection: collectionDisplayName,
                    lablesGroup: allLabelGroupIds,
                    hotkey: nil,
                    labelHotkeys: nil,
                    mapEnabled: false,
                    isInterval: true
                )
                tagByName[primary] = tag
                tagOrder.append(primary)
            }
        }

        guard !tagOrder.isEmpty else {
            throw DartfishXMLImportError.noEvents
        }

        let groupId = UUID().uuidString
        let tagGroup = TagGroup(id: groupId, name: ^String.Titles.xmlImportTagGroupName, tags: tagOrder.map { tagByName[$0]!.id })

        func stamp(for event: DartfishMutableEvent, tag: Tag) -> TimelineStamp {
            let labelStructs: [FullLabelWithGroup] = event.categories.compactMap { cat in
                guard let gid = labelGroupIdByName[cat.name],
                      let lid = labelIdByNameValue["\(cat.name)\u{1}\(cat.value)"] else { return nil }
                return FullLabelWithGroup(id: lid, name: cat.value, description: "", lableGroupId: gid)
            }
            return TimelineStamp(
                tagRefs: [StampTagRef(id: tag.id, tagGroupId: groupId)],
                primaryID: tag.primaryID,
                timeStartSeconds: event.start,
                timeFinishSeconds: event.end,
                colorHex: tag.color,
                label: tag.name,
                labels: labelStructs,
                timeEvents: []
            )
        }

        let timelines: [TimelineLine] = tagOrder.map { name in
            let tag = tagByName[name]!
            let lineStamps = events.enumerated()
                .filter { primaryNameByEventIndex[$0.offset] == name }
                .map { $0.element }
                .sorted { $0.start < $1.start }
                .map { stamp(for: $0, tag: tag) }
            return TimelineLine(
                id: UUID(),
                name: name,
                stamps: lineStamps,
                tagIdForMode: tag.id
            )
        }

        let customCollection = CustomCollectionExport(
            name: collectionDisplayName,
            tags: tagOrder.map { tagByName[$0]! },
            tagGroups: [tagGroup],
            labelGroups: labelGroups,
            labels: labels,
            timeEvents: [],
            playField: nil
        )

        return ProjectImportModel(
            version: "1.0",
            exportDate: Date(),
            projectName: projectTitle,
            videoMetadata: VideoMetadata(),
            timelines: timelines,
            customName: nil,
            isFavorite: false,
            projectId: "",
            customCollection: customCollection
        )
    }
}
