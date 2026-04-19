//
//  ScrollView+Convenience.swift
//  Youchip-Stat
//
//  Created by Alan Erkenov on 19.04.2026.
//

import SwiftUI

extension ScrollView {
    
    @ViewBuilder
    func hideScrollIndicators() -> some View {
        if #available(macOS 13.0, *) {
            self.scrollIndicators(.hidden)
        } else {
            self
        }
    }
}
