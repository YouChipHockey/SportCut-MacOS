//
//  SportcodeXMLProjectImporter.swift
//  Youchip-Stat
//
//  Parses Sportcode / Angels / Wyscout-style XML (ALL_INSTANCES + optional ROWS)
//  into ProjectImportModel with a synthetic custom collection.
//

import Foundation

enum SportcodeXMLImportError: LocalizedError {
    case noInstances
    case parseFailed
    
    var errorDescription: String? {
        switch self {
        case .noInstances:
            return ^String.Titles.xmlImportNoInstancesError
        case .parseFailed:
            return ^String.Titles.xmlImportParseFailedError
        }
    }
}

private final class MutableInstance {
    var start: Double = 0
    var end: Double = 0
    var code: String = ""
    /// Wyscout-style event name from nested label/text.
    var labelText: String = ""
    var freeText: String?
}

private final class SportcodeXMLParserDelegate: NSObject, XMLParserDelegate {
    struct RowColor {
        var code: String = ""
        var r: Int = 0
        var g: Int = 0
        var b: Int = 0
    }
    
    private var instances: [(start: Double, end: Double, code: String, freeText: String?)] = []
    private var codeToHex: [String: String] = [:]
    
    private var currentText = ""
    private var inInstance = false
    private var inLabel = false
    private var inRow = false
    private var currentInstance: MutableInstance?
    private var currentRow = RowColor()
    
    func resultInstances() -> [(start: Double, end: Double, code: String, freeText: String?)] { instances }
    func resultCodeColors() -> [String: String] { codeToHex }
    
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }
    
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        currentText = ""
        switch elementName {
        case "instance":
            inInstance = true
            inLabel = false
            currentInstance = MutableInstance()
        case "label":
            if inInstance { inLabel = true }
        case "row":
            inRow = true
            currentRow = RowColor()
        default:
            break
        }
    }
    
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let text = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        defer { currentText = "" }
        
        switch elementName {
        case "instance":
            if let m = currentInstance {
                let codeTrim = m.code.trimmingCharacters(in: .whitespacesAndNewlines)
                let labelTrim = m.labelText.trimmingCharacters(in: .whitespacesAndNewlines)
                let effectiveCode = codeTrim.isEmpty ? labelTrim : codeTrim
                let note: String? = {
                    if let ft = m.freeText, !ft.isEmpty { return ft }
                    if !codeTrim.isEmpty && !labelTrim.isEmpty { return labelTrim }
                    return nil
                }()
                if !effectiveCode.isEmpty, m.end >= m.start {
                    instances.append((m.start, m.end, effectiveCode, note))
                }
            }
            currentInstance = nil
            inInstance = false
        case "label":
            inLabel = false
        case "row":
            let trimmed = currentRow.code.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                codeToHex[trimmed] = Self.hexFrom65k(r: currentRow.r, g: currentRow.g, b: currentRow.b)
            }
            inRow = false
        case "start":
            if inInstance { currentInstance?.start = Double(text) ?? 0 }
        case "end":
            if inInstance { currentInstance?.end = Double(text) ?? 0 }
        case "code":
            if inInstance {
                currentInstance?.code = text
            } else if inRow {
                currentRow.code = text
            }
        case "free_text":
            if inInstance, !text.isEmpty {
                currentInstance?.freeText = text
            }
        case "text":
            if inInstance, inLabel, !text.isEmpty {
                currentInstance?.labelText = text
            }
        case "R":
            if inRow { currentRow.r = Int(text) ?? 0 }
        case "G":
            if inRow { currentRow.g = Int(text) ?? 0 }
        case "B":
            if inRow { currentRow.b = Int(text) ?? 0 }
        default:
            break
        }
    }
    
    /// Reverse of FullControlView hexToRGB65k: components are 0…65535.
    private static func hexFrom65k(r: Int, g: Int, b: Int) -> String {
        let r8 = min(255, max(0, (r * 255) / 65535))
        let g8 = min(255, max(0, (g * 255) / 65535))
        let b8 = min(255, max(0, (b * 255) / 65535))
        return String(format: "%02X%02X%02X", r8, g8, b8)
    }
}

enum SportcodeXMLProjectImporter {
    
    private static let defaultImportedTagColor = "4A90D9"
    
    /// `XMLParser` expects UTF-8. Sportcode exports and some tools save XML as UTF-16 (with or without BOM).
    private static func xmlDataAsUTF8(_ data: Data) -> Data {
        guard data.count >= 2 else { return data }
        // UTF-8 BOM
        if data.count >= 3, data[0] == 0xEF, data[1] == 0xBB, data[2] == 0xBF {
            return Data(data.dropFirst(3))
        }
        // UTF-16 LE BOM
        if data[0] == 0xFF, data[1] == 0xFE {
            if let s = String(data: data, encoding: .utf16LittleEndian) {
                return Data(Self.stripXMLBOMCharacter(s).utf8)
            }
        }
        // UTF-16 BE BOM
        if data[0] == 0xFE, data[1] == 0xFF {
            if let s = String(data: data, encoding: .utf16BigEndian) {
                return Data(Self.stripXMLBOMCharacter(s).utf8)
            }
        }
        // UTF-16 without BOM: `<` is 0x3C 0x00 (LE) or 0x00 0x3C (BE)
        if data[0] == 0x3C, data[1] == 0x00 {
            if let s = String(data: data, encoding: .utf16LittleEndian) {
                return Data(s.utf8)
            }
        }
        if data[0] == 0x00, data[1] == 0x3C {
            if let s = String(data: data, encoding: .utf16BigEndian) {
                return Data(s.utf8)
            }
        }
        return data
    }
    
    private static func stripXMLBOMCharacter(_ string: String) -> String {
        if string.first == "\u{FEFF}" {
            return String(string.dropFirst())
        }
        return string
    }
    
    static func makeProjectImport(from xmlData: Data, fileName: String) throws -> ProjectImportModel {
        let delegate = SportcodeXMLParserDelegate()
        let parser = XMLParser(data: Self.xmlDataAsUTF8(xmlData))
        parser.delegate = delegate
        guard parser.parse() else {
            throw SportcodeXMLImportError.parseFailed
        }

        var rawInstances = delegate.resultInstances()
        if rawInstances.isEmpty {
            throw SportcodeXMLImportError.noInstances
        }
        rawInstances.sort { $0.start < $1.start }

        let codeColors = delegate.resultCodeColors()
        let projectTitle = (fileName as NSString).deletingPathExtension

        let collectionDisplayName = ^String.Titles.xmlImportCollectionDisplayName

        // --- Build tags from `code` values ---
        var uniqueCodes: [String] = []
        var seenCodes = Set<String>()
        for inst in rawInstances {
            if seenCodes.insert(inst.code).inserted {
                uniqueCodes.append(inst.code)
            }
        }

        var tagByCode: [String: Tag] = [:]
        var tagIds: [String] = []

        for code in uniqueCodes {
            let id = UUID().uuidString
            let color = codeColors[code] ?? defaultImportedTagColor
            let tag = Tag(
                id: id,
                primaryID: nil,
                name: code,
                description: "",
                color: color,
                defaultTimeBefore: 1.0,
                defaultTimeAfter: 1.0,
                collection: collectionDisplayName,
                lablesGroup: [],
                hotkey: nil,
                labelHotkeys: nil,
                mapEnabled: false,
                isInterval: true
            )
            tagByCode[code] = tag
            tagIds.append(id)
        }

        let groupId = UUID().uuidString
        let tagGroup = TagGroup(id: groupId, name: ^String.Titles.xmlImportTagGroupName, tags: tagIds)

        // --- Build labels from `label.text` values (e.g. "Passes", "Interceptions") ---
        // These are real labels attached to tags, not notes.
        var labels: [Label] = []
        var labelGroupLabels: [String] = []
        var labelTextToId: [String: String] = [:]

        for inst in rawInstances {
            // label.text → real label; freeText → also a label
            for text in [inst.freeText].compactMap({ $0 }) + (inst.code.isEmpty ? [] : []) {
                // handled below
                _ = text
            }
        }

        // Collect unique label texts from label.text field
        // In the XML, labelText is stored in freeText when code is present (see parser line 88)
        // freeText contains the label text extracted from <label><text>
        for inst in rawInstances {
            if let note = inst.freeText, !note.isEmpty {
                if labelTextToId[note] == nil {
                    let lid = UUID().uuidString
                    labelTextToId[note] = lid
                    labels.append(Label(id: lid, name: note, description: ""))
                    labelGroupLabels.append(lid)
                }
            }
        }

        var labelGroups: [LabelGroupData] = []
        let labelGroupId: String?
        if !labels.isEmpty {
            let lgId = UUID().uuidString
            labelGroups.append(LabelGroupData(id: lgId, name: ^String.Titles.xmlImportNotesLabelGroupName, lables: labelGroupLabels))
            labelGroupId = lgId
        } else {
            labelGroupId = nil
        }

        // Attach label group to all tags
        var tagsWithLabelGroups: [Tag] = uniqueCodes.map { tagByCode[$0]! }
        if let lgId = labelGroupId {
            tagsWithLabelGroups = tagsWithLabelGroups.map { t in
                var copy = t
                copy.lablesGroup = [lgId]
                return copy
            }
            // Update tagByCode with label groups for stamp creation
            for code in uniqueCodes {
                if var tag = tagByCode[code] {
                    tag.lablesGroup = [lgId]
                    tagByCode[code] = tag
                }
            }
        }

        func stampForInstance(_ inst: (start: Double, end: Double, code: String, freeText: String?)) -> TimelineStamp {
            let tag = tagByCode[inst.code]!
            var labelStructs: [FullLabelWithGroup] = []
            if let ft = inst.freeText, !ft.isEmpty, let lid = labelTextToId[ft], let lgId = labelGroupId {
                labelStructs = [FullLabelWithGroup(id: lid, name: ft, description: "", lableGroupId: lgId)]
            }
            return TimelineStamp(
                tagRefs: [StampTagRef(id: tag.id, tagGroupId: groupId)],
                primaryID: tag.primaryID,
                timeStartSeconds: inst.start,
                timeFinishSeconds: inst.end,
                colorHex: tag.color,
                label: tag.name,
                labels: labelStructs,
                timeEvents: []
            )
        }

        let timelines: [TimelineLine] = uniqueCodes.map { code in
            let tag = tagByCode[code]!
            let lineStamps = rawInstances
                .filter { $0.code == code }
                .sorted { $0.start < $1.start }
                .map { stampForInstance($0) }
            return TimelineLine(
                id: UUID(),
                name: code,
                stamps: lineStamps,
                tagIdForMode: tag.id
            )
        }

        let customCollection = CustomCollectionExport(
            name: collectionDisplayName,
            tags: tagsWithLabelGroups,
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
