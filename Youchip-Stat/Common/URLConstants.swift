//
//  URLConstants.swift
//  Youchip-Stat
//
//  Created by Alan Erkenov on 13.12.2025.
//

import Foundation

class URLConstants {
    
    static let collectionsFolder = "YouChip-Stat/Collections/"
    
    static func getCollecitonFolderStringUrl(with id: String) -> String {
        let collectionFolderUrl = collectionsFolder.appending(id)
        return collectionFolderUrl
    }
    
    static var siteHost: String {
        let currentLocale = Bundle.main.preferredLocalizations.first ?? Locale.current.identifier
        return currentLocale.hasPrefix("ru") ? "sportcut.youchip.pro" : "sportcut.pro"
    }
    
}
