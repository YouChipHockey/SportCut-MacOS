//
//  KeyBindingClipboard.swift
//  Youchip-Stat
//
//  Буфер обмена для связок клавиш (Cmd+C / Cmd+V, дублирование).
//

import AppKit
import Foundation

struct KeyBindingClipboard {

    static let pasteboardType = NSPasteboard.PasteboardType("com.youchip.keybindings")

    // MARK: - Copy

    /// Записать массив связок в буфер обмена.
    static func copy(_ bindings: [KeyBinding]) {
        guard let data = try? JSONEncoder().encode(bindings) else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setData(data, forType: pasteboardType)
    }

    // MARK: - Paste

    /// Прочитать связки из буфера обмена, переназначить sourceId/sourceKind на новый источник.
    /// - Parameters:
    ///   - newSourceId: Новый идентификатор кнопки-источника.
    ///   - newSourceKind: Тип кнопки-источника.
    /// - Returns: Массив новых связок с обновлёнными id и source. nil если буфер пуст или несовместим.
    static func paste(newSourceId: String, newSourceKind: CanvasButtonKind) -> [KeyBinding]? {
        let pb = NSPasteboard.general
        guard let data = pb.data(forType: pasteboardType),
              let decoded = try? JSONDecoder().decode([KeyBinding].self, from: data),
              !decoded.isEmpty else {
            return nil
        }
        return decoded.map { original in
            KeyBinding(
                id: UUID().uuidString,
                sourceId: newSourceId,
                sourceKind: newSourceKind,
                targetId: original.targetId,
                targetKind: original.targetKind,
                type: original.type,
                delaySeconds: original.delaySeconds,
                overrideTimeBefore: original.overrideTimeBefore,
                overrideTimeAfter: original.overrideTimeAfter,
                highlightHotkey: original.highlightHotkey,
                showTargetOnHighlight: original.showTargetOnHighlight,
                revertVisibilityAfterPress: original.revertVisibilityAfterPress
            )
        }
    }

    // MARK: - Duplicate

    /// Дублировать связки (новые id, тот же source).
    static func duplicate(_ bindings: [KeyBinding]) -> [KeyBinding] {
        bindings.map { original in
            KeyBinding(
                id: UUID().uuidString,
                sourceId: original.sourceId,
                sourceKind: original.sourceKind,
                targetId: original.targetId,
                targetKind: original.targetKind,
                type: original.type,
                delaySeconds: original.delaySeconds,
                overrideTimeBefore: original.overrideTimeBefore,
                overrideTimeAfter: original.overrideTimeAfter,
                highlightHotkey: original.highlightHotkey,
                showTargetOnHighlight: original.showTargetOnHighlight,
                revertVisibilityAfterPress: original.revertVisibilityAfterPress
            )
        }
    }

    /// Проверить, есть ли совместимые данные в буфере.
    static var hasContent: Bool {
        NSPasteboard.general.data(forType: pasteboardType) != nil
    }
}
