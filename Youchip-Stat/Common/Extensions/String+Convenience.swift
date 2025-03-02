//
//  String+Convenience.swift
//  smm-printer-mac
//
//  Created by Сергей Бекезин on 26.06.2024.
//

import Foundation

extension String: LocalizedError {
    
    public var errorDescription: String? {
        return self
    }
    
    func cutString() -> String {
        if self.count > 10 {
            let start = self.prefix(6)
            let end = self.suffix(1)
            return "\(start)...\(end)"
        } else {
            return self
        }
    }
    
}
