//
//  MarkupCSVExporter.swift
//  Youchip-Stat
//
//  CSV-экспорт разметки. Два формата:
//   • «По таймлайнам» — строка = штамп (тег на таймлайне), лейблы сгруппированы по колонкам-группам.
//   • «По тегам» — строка = штамп выбранных тегов, отдельная колонка на каждый лейбл (матрица).
//  CSV удобен для последующего форматирования / импорта в другие сервисы.
//

import Foundation

/// Резолвер имён — чтобы экспортёр работал и в разметке (TagLibrary), и в просмотре (источники SportCut).
struct CSVNameResolver {
    let tagName: (String) -> String            // по id тега
    let labelName: (String) -> String          // по id лейбла
    let labelGroupName: (String) -> String     // имя группы для id лейбла (или запасное)
    let eventName: (String) -> String          // по id общего события
}

enum MarkupCSVExporter {

    private static let presentMarker = "+"

    // MARK: - Type 1: по таймлайнам (строка = штамп, колонки-группы лейблов)

    static func timelinesCSV(lines: [TimelineLine], selectedLineIDs: Set<UUID>?, resolver: CSVNameResolver) -> String {
        struct Entry { let lineName: String; let stamp: TimelineStamp }

        var entries: [Entry] = []
        for line in lines where !line.isDrawingsTimeline {
            if let sel = selectedLineIDs, !sel.contains(line.id) { continue }
            for stamp in line.stamps {
                entries.append(Entry(lineName: line.name, stamp: stamp))
            }
        }
        entries.sort { $0.stamp.timeStartSeconds < $1.stamp.timeStartSeconds }

        // Группы лейблов, встречающиеся в выбранных штампах (в порядке первого появления).
        var groupOrder: [String] = []
        var seenGroups = Set<String>()
        for entry in entries {
            for labelID in entry.stamp.labelIDs {
                let group = resolver.labelGroupName(labelID)
                if seenGroups.insert(group).inserted { groupOrder.append(group) }
            }
        }
        // Общие события — в порядке первого появления.
        var eventOrder: [String] = []
        var seenEvents = Set<String>()
        for entry in entries {
            for eventID in entry.stamp.timeEvents where seenEvents.insert(eventID).inserted {
                eventOrder.append(eventID)
            }
        }

        var header = ["№", "Таймлайн", "Тег", "Начало, с", "Конец, с", "Длительность, с"]
        header.append(contentsOf: groupOrder)
        if !eventOrder.isEmpty { header.append("События") }

        var rows: [[String]] = [header]
        for (index, entry) in entries.enumerated() {
            let start = entry.stamp.timeStartSeconds
            let end = entry.stamp.timeFinishSeconds

            // Лейблы штампа, сгруппированные по имени группы.
            var byGroup: [String: [String]] = [:]
            for labelID in entry.stamp.labelIDs {
                byGroup[resolver.labelGroupName(labelID), default: []].append(resolver.labelName(labelID))
            }

            var row: [String] = [
                String(index + 1),
                entry.lineName,
                resolver.tagName(entry.stamp.idTag),
                formatSeconds(start),
                formatSeconds(end),
                formatSeconds(max(0, end - start))
            ]
            for group in groupOrder {
                row.append((byGroup[group] ?? []).joined(separator: ", "))
            }
            if !eventOrder.isEmpty {
                let names = entry.stamp.timeEvents.map { resolver.eventName($0) }
                row.append(names.joined(separator: ", "))
            }
            rows.append(row)
        }

        return render(rows)
    }

    // MARK: - Type 2: по тегам (строка = штамп, отдельная колонка на каждый лейбл)

    static func tagsCSV(lines: [TimelineLine], selectedTagIDs: Set<String>?, resolver: CSVNameResolver) -> String {
        struct Entry { let lineName: String; let stamp: TimelineStamp }

        var entries: [Entry] = []
        for line in lines where !line.isDrawingsTimeline {
            for stamp in line.stamps {
                if let sel = selectedTagIDs, !sel.contains(stamp.idTag) { continue }
                entries.append(Entry(lineName: line.name, stamp: stamp))
            }
        }
        entries.sort { $0.stamp.timeStartSeconds < $1.stamp.timeStartSeconds }

        // Универсум лейблов и событий (в порядке первого появления).
        var labelOrder: [String] = []
        var seenLabels = Set<String>()
        for entry in entries {
            for labelID in entry.stamp.labelIDs where seenLabels.insert(labelID).inserted {
                labelOrder.append(labelID)
            }
        }
        var eventOrder: [String] = []
        var seenEvents = Set<String>()
        for entry in entries {
            for eventID in entry.stamp.timeEvents where seenEvents.insert(eventID).inserted {
                eventOrder.append(eventID)
            }
        }

        var header = ["№", "Таймлайн", "Тег", "Начало, с", "Конец, с", "Длительность, с"]
        header.append(contentsOf: labelOrder.map { resolver.labelName($0) })
        header.append(contentsOf: eventOrder.map { resolver.eventName($0) })

        var rows: [[String]] = [header]
        for (index, entry) in entries.enumerated() {
            let start = entry.stamp.timeStartSeconds
            let end = entry.stamp.timeFinishSeconds
            let stampLabels = Set(entry.stamp.labelIDs)
            let stampEvents = Set(entry.stamp.timeEvents)

            var row: [String] = [
                String(index + 1),
                entry.lineName,
                resolver.tagName(entry.stamp.idTag),
                formatSeconds(start),
                formatSeconds(end),
                formatSeconds(max(0, end - start))
            ]
            for labelID in labelOrder {
                row.append(stampLabels.contains(labelID) ? presentMarker : "")
            }
            for eventID in eventOrder {
                row.append(stampEvents.contains(eventID) ? presentMarker : "")
            }
            rows.append(row)
        }

        return render(rows)
    }

    // MARK: - Helpers

    private static func formatSeconds(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    private static func render(_ rows: [[String]]) -> String {
        // UTF-8 BOM — чтобы кириллица корректно открывалась в Excel.
        var out = "\u{FEFF}"
        out += rows.map { row in row.map(escape).joined(separator: ",") }.joined(separator: "\r\n")
        out += "\r\n"
        return out
    }

    private static func escape(_ field: String) -> String {
        if field.contains(",") || field.contains("\"") || field.contains("\n") || field.contains("\r") {
            return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return field
    }
}
