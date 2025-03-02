//
//  UInt64+Convenience.swift
//  smm-printer-mac
//
//  Created by Сергей Бекезин on 03.07.2024.
//

import Foundation

extension UInt64 {
    
    func formatBytes() -> String {
        let byteCountFormatter = ByteCountFormatter()
        byteCountFormatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB, .useTB]
        byteCountFormatter.countStyle = .decimal
        
        let formattedString = byteCountFormatter.string(fromByteCount: Int64(self))
        return formattedString
    }
    
}
