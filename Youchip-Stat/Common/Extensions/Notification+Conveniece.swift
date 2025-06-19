//
//  Notification+Conveniece.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 6/19/25.
//

import SwiftUI
import AVKit
import Cocoa
import AVFoundation
import UniformTypeIdentifiers

extension Notification.Name {
    static let showLabelSheet = Notification.Name("showLabelSheet")
    static let labelHotkeyPressed = Notification.Name("labelHotkeyPressed")
    static let tagUpdated = Notification.Name("tagUpdated")
}
