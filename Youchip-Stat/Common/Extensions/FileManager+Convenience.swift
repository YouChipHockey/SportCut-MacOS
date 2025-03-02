//
//  FileManager+Convenience.swift
//  smm-printer-mac
//
//  Created by Сергей Бекезин on 25.06.2024.
//

import Foundation

extension FileManager {
    
    func createDirectoryIfNeeded(url: URL) {
        if fileExists(atPath: url.path) {
            return
        }
        try? createDirectory(at: url, withIntermediateDirectories: true)
    }
    
}
