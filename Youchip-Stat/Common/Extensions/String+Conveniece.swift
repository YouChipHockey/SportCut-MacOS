//
//  String+Conveniece.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 6/19/25.
//

import SwiftUI
import AVKit
import Cocoa
import AVFoundation
import UniformTypeIdentifiers

extension String {
    
    func size(withAttributes attributes: [NSAttributedString.Key: Any]) -> CGSize {
        let string = self as NSString
        return string.size(withAttributes: attributes)
    }
    
    /// Измерение с кэшем. Реальная разметка текста (`size(withAttributes:)`) стоит дорого, а зовут
    /// её в горячем пути: `StampLabelsOverlayView` подбирает набор чипов, помещающихся в штамп, —
    /// то есть на каждый лейбл каждого штампа, и заново при каждом зуме таймлайна. Строк мало
    /// (имена тегов и лейблов), поэтому кэш не растёт. См. TASK-007, 3.6.
    ///
    /// Только главный поток — как и вся отрисовка, из которой зовётся.
    func size(withSystemFontOfSize fontSize: CGFloat) -> CGSize {
        let key = TextSizeCache.Key(text: self, fontSize: fontSize)
        if let cached = TextSizeCache.storage[key] { return cached }

        let font = NSFont.systemFont(ofSize: fontSize)
        let attributes = [NSAttributedString.Key.font: font]
        let measured = size(withAttributes: attributes)
        TextSizeCache.storage[key] = measured
        return measured
    }

}

/// Хранилище кэша измерений текста для `String.size(withSystemFontOfSize:)`.
enum TextSizeCache {

    struct Key: Hashable {
        let text: String
        let fontSize: CGFloat
    }

    static var storage: [Key: CGSize] = [:]
}
