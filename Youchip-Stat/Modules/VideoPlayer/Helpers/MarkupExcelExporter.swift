//
//  MarkupExcelExporter.swift
//  Youchip-Stat
//
//  Экспорт разметки (таймлайнов со штампами) в формат Excel (.xlsx).
//  Генерирует валидный xlsx-файл без внешних зависимостей: минимальный
//  OOXML-пакет упаковывается собственным ZIP-писателем (метод "stored"),
//  что безопасно в песочнице (без запуска внешних утилит).
//

import Foundation

enum MarkupExcelExporter {

    // MARK: - Public API

    /// Маркер наличия лейбла у штампа.
    private static let presentMarker = "+"

    /// Собирает xlsx из таймлайнов разметки. Строки — по одному штампу, отсортированы по времени начала.
    /// Каждый использованный лейбл получает отдельную колонку с маркером «есть/нет» у штампа.
    static func makeWorkbookData(lines: [TimelineLine], tagLibrary: TagLibraryManager) -> Data {
        struct Entry {
            let lineName: String
            let stamp: TimelineStamp
            let tagName: String
        }

        var entries: [Entry] = []
        for line in lines {
            if line.isDrawingsTimeline { continue }
            for stamp in line.stamps {
                let tag = tagLibrary.findTagById(stamp.idTag)
                let tagName = tag?.name ?? stamp.label
                entries.append(Entry(lineName: line.name, stamp: stamp, tagName: tagName))
            }
        }
        entries.sort { $0.stamp.timeStartSeconds < $1.stamp.timeStartSeconds }

        // Универсум лейблов — все, что встречаются в разметке (в порядке первого появления).
        var labelOrder: [String] = []
        var seenLabels = Set<String>()
        var labelName: [String: String] = [:]
        for entry in entries {
            for labelID in entry.stamp.labelIDs where seenLabels.insert(labelID).inserted {
                labelOrder.append(labelID)
                labelName[labelID] = tagLibrary.findLabelById(labelID)?.name ?? labelID
            }
        }

        // Универсум общих событий — по тому же принципу (в порядке первого появления).
        var eventOrder: [String] = []
        var seenEvents = Set<String>()
        var eventName: [String: String] = [:]
        for entry in entries {
            for eventID in entry.stamp.timeEvents where seenEvents.insert(eventID).inserted {
                eventOrder.append(eventID)
                eventName[eventID] = tagLibrary.allTimeEvents.first(where: { $0.id == eventID })?.name ?? eventID
            }
        }

        var rows: [[Cell]] = []

        // Заголовок: фиксированные колонки + по колонке на каждый лейбл + по колонке на каждое общее событие.
        var header: [Cell] = [
            .text("№"), .text("Таймлайн"), .text("Код"),
            .text("Начало, с"), .text("Конец, с"), .text("Длительность, с")
        ]
        for labelID in labelOrder {
            header.append(.text(labelName[labelID] ?? labelID))
        }
        for eventID in eventOrder {
            header.append(.text(eventName[eventID] ?? eventID))
        }
        rows.append(header)

        for (index, entry) in entries.enumerated() {
            let start = entry.stamp.timeStartSeconds
            let end = entry.stamp.timeFinishSeconds
            let stampLabels = Set(entry.stamp.labelIDs)
            let stampEvents = Set(entry.stamp.timeEvents)
            var row: [Cell] = [
                .number(Double(index + 1)),
                .text(entry.lineName),
                .text(entry.tagName),
                .number(start),
                .number(end),
                .number(max(0, end - start))
            ]
            for labelID in labelOrder {
                row.append(.text(stampLabels.contains(labelID) ? presentMarker : ""))
            }
            for eventID in eventOrder {
                row.append(.text(stampEvents.contains(eventID) ? presentMarker : ""))
            }
            rows.append(row)
        }

        return buildXLSX(sheetName: "Разметка", rows: rows)
    }

    // MARK: - Cell

    enum Cell {
        case text(String)
        case number(Double)
    }

    // MARK: - XLSX package

    private static func buildXLSX(sheetName: String, rows: [[Cell]]) -> Data {
        var zip = ZipWriter()
        zip.add("[Content_Types].xml", Data(contentTypesXML.utf8))
        zip.add("_rels/.rels", Data(rootRelsXML.utf8))
        zip.add("xl/workbook.xml", Data(workbookXML(sheetName: sheetName).utf8))
        zip.add("xl/_rels/workbook.xml.rels", Data(workbookRelsXML.utf8))
        zip.add("xl/worksheets/sheet1.xml", Data(sheetXML(rows: rows).utf8))
        return zip.finalize()
    }

    private static let contentTypesXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
    <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
    <Default Extension="xml" ContentType="application/xml"/>
    <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
    <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
    </Types>
    """

    private static let rootRelsXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
    <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
    </Relationships>
    """

    private static func workbookXML(sheetName: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
        <sheets>
        <sheet name="\(escapeXML(sheetName))" sheetId="1" r:id="rId1"/>
        </sheets>
        </workbook>
        """
    }

    private static let workbookRelsXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
    <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
    </Relationships>
    """

    private static func sheetXML(rows: [[Cell]]) -> String {
        var body = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n"
        body += "<worksheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\"><sheetData>"
        for (rowIndex, cells) in rows.enumerated() {
            let rowNum = rowIndex + 1
            body += "<row r=\"\(rowNum)\">"
            for (colIndex, cell) in cells.enumerated() {
                let ref = "\(columnLetter(colIndex))\(rowNum)"
                switch cell {
                case .text(let s):
                    // Пустые ячейки не пишем — в Excel они и так пустые (ссылки на ячейки явные).
                    if s.isEmpty { continue }
                    body += "<c r=\"\(ref)\" t=\"inlineStr\"><is><t xml:space=\"preserve\">\(escapeXML(s))</t></is></c>"
                case .number(let d):
                    body += "<c r=\"\(ref)\"><v>\(numberString(d))</v></c>"
                }
            }
            body += "</row>"
        }
        body += "</sheetData></worksheet>"
        return body
    }

    // MARK: - Helpers

    private static func escapeXML(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
         .replacingOccurrences(of: "\"", with: "&quot;")
         .replacingOccurrences(of: "'", with: "&apos;")
    }

    /// 0 → "A", 25 → "Z", 26 → "AA".
    private static func columnLetter(_ index: Int) -> String {
        var n = index
        var s = ""
        repeat {
            let r = n % 26
            s = String(UnicodeScalar(65 + r)!) + s
            n = n / 26 - 1
        } while n >= 0
        return s
    }

    /// Число без «хвоста» плавающей точки: целые — как целые, дробные — до 3 знаков.
    private static func numberString(_ d: Double) -> String {
        if d == d.rounded() { return String(Int(d)) }
        var s = String(format: "%.3f", d)
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s
    }
}

// MARK: - Minimal ZIP writer (stored / no compression)

private struct ZipWriter {

    private struct Entry {
        let name: String
        let size: Int
        let crc: UInt32
        let offset: UInt32
    }

    private var entries: [Entry] = []
    private var buffer = Data()

    mutating func add(_ name: String, _ content: Data) {
        let nameBytes = Array(name.utf8)
        let crc = ZipWriter.crc32(content)
        let offset = UInt32(buffer.count)

        // Local file header
        buffer.append(le32(0x04034b50))
        buffer.append(le16(20))                       // version needed
        buffer.append(le16(0))                        // flags
        buffer.append(le16(0))                        // compression = stored
        buffer.append(le16(0))                        // mod time
        buffer.append(le16(0x21))                     // mod date (1980-01-01)
        buffer.append(le32(crc))
        buffer.append(le32(UInt32(content.count)))    // compressed size
        buffer.append(le32(UInt32(content.count)))    // uncompressed size
        buffer.append(le16(UInt16(nameBytes.count)))
        buffer.append(le16(0))                        // extra length
        buffer.append(contentsOf: nameBytes)
        buffer.append(content)

        entries.append(Entry(name: name, size: content.count, crc: crc, offset: offset))
    }

    mutating func finalize() -> Data {
        let centralStart = UInt32(buffer.count)
        var central = Data()
        for entry in entries {
            let nameBytes = Array(entry.name.utf8)
            central.append(le32(0x02014b50))
            central.append(le16(20))                  // version made by
            central.append(le16(20))                  // version needed
            central.append(le16(0))                   // flags
            central.append(le16(0))                   // compression
            central.append(le16(0))                   // mod time
            central.append(le16(0x21))                // mod date
            central.append(le32(entry.crc))
            central.append(le32(UInt32(entry.size)))  // compressed size
            central.append(le32(UInt32(entry.size)))  // uncompressed size
            central.append(le16(UInt16(nameBytes.count)))
            central.append(le16(0))                   // extra length
            central.append(le16(0))                   // comment length
            central.append(le16(0))                   // disk number start
            central.append(le16(0))                   // internal attrs
            central.append(le32(0))                   // external attrs
            central.append(le32(entry.offset))
            central.append(contentsOf: nameBytes)
        }
        buffer.append(central)

        // End of central directory
        buffer.append(le32(0x06054b50))
        buffer.append(le16(0))                        // disk number
        buffer.append(le16(0))                        // cd start disk
        buffer.append(le16(UInt16(entries.count)))
        buffer.append(le16(UInt16(entries.count)))
        buffer.append(le32(UInt32(central.count)))
        buffer.append(le32(centralStart))
        buffer.append(le16(0))                        // comment length

        return buffer
    }

    // MARK: Byte helpers

    private func le16(_ v: UInt16) -> Data {
        Data([UInt8(v & 0xff), UInt8((v >> 8) & 0xff)])
    }

    private func le32(_ v: UInt32) -> Data {
        Data([
            UInt8(v & 0xff),
            UInt8((v >> 8) & 0xff),
            UInt8((v >> 16) & 0xff),
            UInt8((v >> 24) & 0xff)
        ])
    }

    static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xEDB88320 : crc >> 1
            }
        }
        return crc ^ 0xFFFFFFFF
    }
}
