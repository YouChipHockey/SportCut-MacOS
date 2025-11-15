//
//  LineStyle.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 9/6/25.
//

import AppKit
import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

enum LineStyle: String, CaseIterable {
    case solid = "solid"
    case dashed = "dashed"
    
    var displayName: String {
        switch self {
        case .solid:
            return ^String.Titles.solid
        case .dashed:
            return ^String.Titles.dashedLine
        }
    }
}
