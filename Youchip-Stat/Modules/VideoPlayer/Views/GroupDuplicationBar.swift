//
//  GroupDuplicationBar.swift
//  Youchip-Stat
//
//  Панель множественного выбора групп: показывает выбранные группы «чипами» и даёт
//  меню «Дублировать в …» со списком других коллекций. Используется в обычном
//  редакторе коллекций и в редакторе связок клавиш.
//

import SwiftUI

struct GroupDuplicationBar: View {

    struct Chip: Identifiable {
        let id: String
        let name: String
    }

    let chips: [Chip]
    /// Коллекции-приёмники (обычно все, кроме текущей открытой).
    let targets: [CollectionInfo]
    let accent: Color
    let onRemoveChip: (String) -> Void
    let onClear: () -> Void
    let onDuplicate: (String) -> Void
    /// Копирование выбранных групп в буфер (для вставки в другую коллекцию). Опционально.
    var onCopy: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(String(format: ^String.Titles.collectionSelectedGroupsCountFormat, chips.count))
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(accent)

                Spacer()

                if let onCopy {
                    Button(action: onCopy) {
                        HStack(spacing: 4) {
                            Image(systemName: "doc.on.doc")
                            Text(^String.Titles.collectionCopyGroup)
                        }
                        .font(.caption)
                        .foregroundColor(accent)
                    }
                    .buttonStyle(PlainButtonStyle())
                }

                duplicateMenu

                Button(action: onClear) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(PlainButtonStyle())
                .help(^String.Titles.collectionClearSelection)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(chips) { chip in
                        chipView(chip)
                    }
                }
                .padding(.bottom, 2)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(accent.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(accent.opacity(0.3), lineWidth: 1)
        )
    }

    private var duplicateMenu: some View {
        Menu {
            if targets.isEmpty {
                Text(^String.Titles.collectionNoOtherCollections)
            } else {
                ForEach(targets, id: \.id) { info in
                    Button(info.name) { onDuplicate(info.id) }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "plus.rectangle.on.folder")
                Text(^String.Titles.collectionDuplicateTo)
            }
            .font(.caption)
            .foregroundColor(accent)
        }
        .menuStyle(BorderlessButtonMenuStyle())
        .fixedSize()
        .disabled(targets.isEmpty)
    }

    private func chipView(_ chip: Chip) -> some View {
        HStack(spacing: 4) {
            Text(chip.name)
                .font(.caption)
                .lineLimit(1)
            Button(action: { onRemoveChip(chip.id) }) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule().fill(accent.opacity(0.15))
        )
        .overlay(
            Capsule().stroke(accent.opacity(0.35), lineWidth: 1)
        )
    }
}
