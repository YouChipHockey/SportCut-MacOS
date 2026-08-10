//
//  SportcodeXMLProjectExporter.swift
//  Youchip-Stat
//
//  Строит Sportcode-совместимый XML (ALL_INSTANCES + ROWS) из таймлайнов проекта.
//  Схема зеркальна SportcodeXMLProjectImporter, чтобы файл читался обратно и сторонними инструментами.
//

import Foundation

enum SportcodeXMLProjectExporter {

    /// Собирает XML из разметки проекта. Один `<instance>` на штамп, `<row>` — цвет для каждого уникального кода.
    static func makeXML(timelines: [TimelineLine]) -> Data {
        struct LabelPair { let group: String; let text: String }
        struct Instance {
            let start: Double
            let end: Double
            let code: String
            let labels: [LabelPair]
            let freeText: String?
        }

        var instances: [Instance] = []
        var codeColorHex: [String: String] = [:]      // код → hex (первый встреченный цвет)
        var codeOrder: [String] = []                  // порядок появления кодов для ROWS

        for line in timelines {
            for stamp in line.stamps {
                let code = stamp.label.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !code.isEmpty else { continue }

                if codeColorHex[code] == nil {
                    codeColorHex[code] = stamp.colorHex
                    codeOrder.append(code)
                }

                let labels: [LabelPair] = stamp.labels.compactMap { lbl in
                    let text = lbl.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty else { return nil }
                    return LabelPair(group: labelGroupName(for: lbl.lableGroupId), text: text)
                }

                let comment = stamp.comment?.trimmingCharacters(in: .whitespacesAndNewlines)
                instances.append(
                    Instance(
                        start: stamp.timeStartSeconds,
                        end: stamp.timeFinishSeconds,
                        code: code,
                        labels: labels,
                        freeText: (comment?.isEmpty == false) ? comment : nil
                    )
                )
            }
        }

        instances.sort { $0.start < $1.start }

        var xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
        xml += "<file>\n"
        xml += "  <ALL_INSTANCES>\n"
        for (idx, inst) in instances.enumerated() {
            xml += "    <instance>\n"
            xml += "      <ID>\(idx + 1)</ID>\n"
            xml += "      <start>\(formatSeconds(inst.start))</start>\n"
            xml += "      <end>\(formatSeconds(inst.end))</end>\n"
            xml += "      <code>\(escape(inst.code))</code>\n"
            for label in inst.labels {
                xml += "      <label>\n"
                if !label.group.isEmpty {
                    xml += "        <group>\(escape(label.group))</group>\n"
                }
                xml += "        <text>\(escape(label.text))</text>\n"
                xml += "      </label>\n"
            }
            if let freeText = inst.freeText {
                xml += "      <free_text>\(escape(freeText))</free_text>\n"
            }
            xml += "    </instance>\n"
        }
        xml += "  </ALL_INSTANCES>\n"

        xml += "  <ROWS>\n"
        for code in codeOrder {
            let (r, g, b) = rgb65k(from: codeColorHex[code] ?? "000000")
            xml += "    <row>\n"
            xml += "      <code>\(escape(code))</code>\n"
            xml += "      <R>\(r)</R>\n"
            xml += "      <G>\(g)</G>\n"
            xml += "      <B>\(b)</B>\n"
            xml += "    </row>\n"
        }
        xml += "  </ROWS>\n"
        xml += "</file>\n"

        return Data(xml.utf8)
    }

    // MARK: - Helpers

    private static func labelGroupName(for id: String) -> String {
        TagLibraryManager.shared.allLabelGroups.first(where: { $0.id == id })?.name ?? ""
    }

    private static func formatSeconds(_ value: Double) -> String {
        String(format: "%.2f", max(0, value))
    }

    private static func escape(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    /// hex "RRGGBB" → компоненты 0…65535 (обратно к `hexFrom65k` импортёра: component8 * 257).
    private static func rgb65k(from hex: String) -> (Int, Int, Int) {
        var h = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if h.hasPrefix("#") { h.removeFirst() }
        guard h.count == 6, let value = Int(h, radix: 16) else { return (0, 0, 0) }
        let r = (value >> 16) & 0xFF
        let g = (value >> 8) & 0xFF
        let b = value & 0xFF
        return (r * 257, g * 257, b * 257)
    }
}
