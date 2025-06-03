//
//  EditorActions.swift
//  smm-printer-mac
//
//  Created by Сергей Бекезин on 08.08.2024.
//

import Foundation

enum EditorAction {
    
    case close
    case share
    case save
    case download
    case showSuccess(result: Bool)
    case changeImage(item: Int)
    case showError(error: String)
    case showInfo(info: String)
    
}
