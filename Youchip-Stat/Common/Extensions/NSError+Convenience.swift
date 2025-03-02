//
//  NSError+Convenience.swift
//  smm-printer-mac
//
//  Created by Сергей Бекезин on 13.06.2024.
//

import Foundation

extension NSError {
    
    static func getErrorWithDescription(_ description: String, code: Int = -1, domain: AnyClass? = nil) -> NSError {
        let domain = String(describing: domain ?? self)
        return NSError(domain: domain, code: code, userInfo: [NSLocalizedDescriptionKey: description])
    }
    
}
