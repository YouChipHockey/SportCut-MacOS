//
//  AppConfig.swift
//  Youchip-Stat
//
//  Created by Alan Erkenov on 25.02.2026.
//

import AVFoundation

class AppConfig {

    static var isDebug: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }

}

extension AVPlayer {
    /// В дебаг-режиме все плееры по умолчанию без звука — чтобы фоновые/зеркальные
    /// плееры не мешали при разработке. В релизе на звук не влияет.
    @discardableResult
    func applyDebugMuteIfNeeded() -> Self {
        if AppConfig.isDebug { isMuted = true }
        return self
    }
}
