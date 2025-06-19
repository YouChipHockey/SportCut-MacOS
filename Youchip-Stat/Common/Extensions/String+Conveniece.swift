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
    
    func size(withSystemFontOfSize fontSize: CGFloat) -> CGSize {
        let font = NSFont.systemFont(ofSize: fontSize)
        let attributes = [NSAttributedString.Key.font: font]
        return size(withAttributes: attributes)
    }
    
}
