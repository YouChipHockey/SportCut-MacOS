//
//  LocalizedStrings.swift
//  smm-printer-mac
//
//  Created by Сергей Бекезин on 04.06.2024.
//

import Foundation

extension String {
    
    func capitalizeFirstLetter() -> String {
        return prefix(1).capitalized + dropFirst()
    }
    
    enum Titles: String {
        case cancelButtonTitle
        case previousButtonTitle
        case alertsOkTitle
        case alertsErrorTitle
        case alertsInfoTitle
        case alertsYesTitle
        case alertsNoTitle
        case alertsAreYouSure
        case alertsLikeAlertTitle
        case alertsOcrErrorTitle
        case alertsOpenFileErrorTitle
        case alertsFileErrorTitle
        case alertsUnknowErrorTitle
        case alertsEmptyFileErrorTitle
        case alertsBadFileErrorTitle
        case addVideoTitle
        case macQuitAppTitle
        case rootYouChipTitle
        case rootVideosTitle
        case rootTheFileIsPlacedInCloudTitle
        case rootDownloadTitle
        case rootDownloadingHasStartedTitle
    }
    
}

extension RawRepresentable {
    
    func format(_ args: CVarArg...) -> String {
        let format = ^self
        return String(format: format, arguments: args)
    }
    
}

prefix operator ^
prefix func ^<Type: RawRepresentable> (_ value: Type) -> String {
    if let raw = value.rawValue as? String {
        let key = raw.capitalizeFirstLetter()
        return NSLocalizedString(key, comment: "")
    }
    return ""
}
