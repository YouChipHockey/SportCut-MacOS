//
//  ClipSearchView.swift
//  Youchip-Stat
//
//  Поиск по клипам: пользователь вводит любой текст, ему предлагается список ТЕГОВ (строка = тег),
//  где текст встречается — в имени тега, в лейбле или в общем событии любого из штампов тега.
//  Совпавший фрагмент подсвечивается жирным. По умолчанию все теги выбраны; выбор применяется
//  по id штампов (через TimelineFilter.searchAllowedStampIDs), поэтому «остаются только клипы с
//  Ивановым» точно, включая совпадения по лейблу/событию. Один UI на разметку и просмотр.
//

import SwiftUI

/// Строка результата поиска — один тег с накопленными совпадениями и id подходящих штампов.
struct ClipSearchTagRow: Identifiable {
    let id: String            // id тега
    let tagName: String
    let colorHex: String
    let nameMatched: Bool     // совпадение по имени тега
    /// ВСЕ лейблы совпавших штампов этого тега (не только совпавшие с запросом) — у тега его лейблы
    /// должны быть видны при любом поиске. Совпадение с запросом внутри подсвечивается жирным.
    let labels: [String]
    let matchedEvents: [String]
    let stampIDs: Set<UUID>   // штампы этого тега, попавшие под запрос
}

enum ClipSearch {
    static func normalized(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Строит строки-теги по запросу. Имена резолвятся снаружи (в разметке — через библиотеку,
    /// в просмотре — из источника), чтобы компонент не зависел от контекста.
    static func buildRows(
        stamps: [TimelineStamp],
        query: String,
        tagID: (TimelineStamp) -> String?,
        tagName: (TimelineStamp) -> String,
        labelNames: (TimelineStamp) -> [String],
        eventNames: (TimelineStamp) -> [String]
    ) -> [ClipSearchTagRow] {
        let q = normalized(query)
        guard !q.isEmpty else { return [] }

        struct Acc {
            let id: String
            let tagName: String
            let colorHex: String
            var nameMatched = false
            /// ВСЕ лейблы совпавших штампов (не только совпавшие с запросом).
            var allLabels = Set<String>()
            var events = Set<String>()
            var stampIDs = Set<UUID>()
        }
        var byTag: [String: Acc] = [:]

        for stamp in stamps {
            guard let tid = tagID(stamp), !tid.isEmpty else { continue }
            let name = tagName(stamp)
            let labels = labelNames(stamp)
            let events = eventNames(stamp)

            let nameHit = name.lowercased().contains(q)
            let labelHits = labels.filter { $0.lowercased().contains(q) }
            let eventHits = events.filter { $0.lowercased().contains(q) }
            guard nameHit || !labelHits.isEmpty || !eventHits.isEmpty else { continue }

            var acc = byTag[tid] ?? Acc(id: tid, tagName: name, colorHex: stamp.colorHex)
            if nameHit { acc.nameMatched = true }
            // Показываем ВСЕ лейблы совпавшего штампа — чтобы у тега его лейблы были видны при любом
            // поиске (по имени тега они раньше не показывались вовсе). Совпадение подсветится жирным.
            acc.allLabels.formUnion(labels)
            acc.events.formUnion(eventHits)
            acc.stampIDs.insert(stamp.id)
            byTag[tid] = acc
        }

        return byTag.values
            .map {
                ClipSearchTagRow(
                    id: $0.id, tagName: $0.tagName, colorHex: $0.colorHex,
                    nameMatched: $0.nameMatched,
                    labels: $0.allLabels.sorted(), matchedEvents: $0.events.sorted(),
                    stampIDs: $0.stampIDs
                )
            }
            .sorted { $0.tagName.localizedCaseInsensitiveCompare($1.tagName) == .orderedAscending }
    }

    /// `Text` с жирной подсветкой первого вхождения запроса (регистронезависимо).
    static func highlighted(_ text: String, query: String, size: CGFloat = 12) -> Text {
        let plain = Text(text).font(.system(size: size))
        let q = normalized(query)
        guard !q.isEmpty,
              let range = text.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) else {
            return plain
        }
        let pre = String(text[text.startIndex..<range.lowerBound])
        let match = String(text[range])
        let post = String(text[range.upperBound...])
        return Text(pre).font(.system(size: size))
            + Text(match).font(.system(size: size, weight: .bold)).foregroundColor(.primary)
            + Text(post).font(.system(size: size))
    }
}

/// Список результатов поиска по клипам (строки-теги с чекбоксами). Управляет выбором тегов;
/// применение к таймлайну/таблице делает вызывающий (через `TimelineFilter.searchAllowedStampIDs`).
struct ClipSearchResultsList: View {
    let rows: [ClipSearchTagRow]
    let query: String
    @Binding var selectedTagIDs: Set<String>

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text("\(^String.Titles.sportCutFilterFound): \(rows.count)")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Spacer()
                if !rows.isEmpty {
                    Button(^String.Titles.sportCutSelectAll) {
                        selectedTagIDs = Set(rows.map(\.id))
                    }
                    .buttonStyle(PlainButtonStyle())
                    .font(.system(size: 11))
                    .foregroundColor(.blue)
                    Button(^String.Titles.viewingDeselectAll) {
                        selectedTagIDs = []
                    }
                    .buttonStyle(PlainButtonStyle())
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                }
            }

            if rows.isEmpty {
                Text(^String.Titles.nothingFound)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .padding(.top, 4)
            } else {
                ForEach(rows) { row in
                    rowView(row)
                }
            }
        }
    }

    @ViewBuilder
    private func rowView(_ row: ClipSearchTagRow) -> some View {
        let isSelected = selectedTagIDs.contains(row.id)
        Button(action: {
            if isSelected { selectedTagIDs.remove(row.id) } else { selectedTagIDs.insert(row.id) }
        }) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .foregroundColor(isSelected ? .blue : .gray)
                    .font(.system(size: 13))
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Circle().fill(Color(hex: row.colorHex)).frame(width: 7, height: 7)
                        ClipSearch.highlighted(row.tagName, query: row.nameMatched ? query : "", size: 12)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Text("\(row.stampIDs.count)")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    // Лейблы тега (все) + совпавшие события. Лейблы видны всегда, совпадение с
                    // запросом внутри — жирным (см. subMatchesText → highlighted).
                    let subMatches = row.labels + row.matchedEvents
                    if !subMatches.isEmpty {
                        subMatchesText(subMatches)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? Color.blue.opacity(0.08) : Color.gray.opacity(0.05))
            .cornerRadius(6)
        }
        .buttonStyle(PlainButtonStyle())
    }

    /// Совпавшие лейблы/события через запятую, каждый — с жирной подсветкой запроса.
    private func subMatchesText(_ items: [String]) -> Text {
        var result = Text("")
        for (i, item) in items.enumerated() {
            if i > 0 { result = result + Text(", ").font(.system(size: 11)) }
            result = result + ClipSearch.highlighted(item, query: query, size: 11)
        }
        return result
    }
}
