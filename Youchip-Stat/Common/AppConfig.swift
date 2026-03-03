//
//  AppConfig.swift
//  Youchip-Stat
//
//  Created by Alan Erkenov on 25.02.2026.
//

class AppConfig {
    
    static var isDebug: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }
    
}
