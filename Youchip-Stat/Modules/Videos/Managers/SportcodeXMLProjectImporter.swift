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
            currentInstance = MutableInstance()
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
                let trimmedCode = m.code.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmedCode.isEmpty, m.end >= m.start {
                    instances.append((m.start, m.end, trimmedCode, m.freeText))
                }
            }
            currentInstance = nil
            inInstance = false
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
    
    static func makeProjectImport(from xmlData: Data, fileName: String) throws -> ProjectImportModel {
        let delegate = SportcodeXMLParserDelegate()
        let parser = XMLParser(data: xmlData)
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
        
        let tags: [Tag] = uniqueCodes.map { tagByCode[$0]! }
        
        var labels: [Label] = []
        var labelGroupLabels: [String] = []
        var freeTextToLabelId: [String: String] = [:]
        
        for inst in rawInstances {
            guard let note = inst.freeText, !note.isEmpty else { continue }
            if freeTextToLabelId[note] != nil { continue }
            let lid = UUID().uuidString
            freeTextToLabelId[note] = lid
            labels.append(Label(id: lid, name: note, description: ""))
            labelGroupLabels.append(lid)
        }
        
        var labelGroups: [LabelGroupData] = []
        if !labels.isEmpty {
            let lgId = UUID().uuidString
            labelGroups.append(LabelGroupData(id: lgId, name: ^String.Titles.xmlImportNotesLabelGroupName, lables: labelGroupLabels))
        }
        
        var tagsWithLabelGroups = tags
        if let firstLG = labelGroups.first {
            tagsWithLabelGroups = tags.map { t in
                var copy = t
                copy.lablesGroup = [firstLG.id]
                return copy
            }
        }
        
        func stampForInstance(_ inst: (start: Double, end: Double, code: String, freeText: String?)) -> TimelineStamp {
            let tag = tagByCode[inst.code]!
            let labelStructs: [FullLabelWithGroup]
            if let ft = inst.freeText, let lid = freeTextToLabelId[ft], let lgId = labelGroups.first?.id {
                labelStructs = [FullLabelWithGroup(id: lid, name: ft, description: "", lableGroupId: lgId)]
            } else {
                labelStructs = []
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
