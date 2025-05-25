//
//  NSApplication + Convenience.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 06.05.2025.
//

import Foundation
import SwiftUI

extension NSApplication {
    func preventKeyEquivalent() {
        DispatchQueue.main.async {}
    }
}
