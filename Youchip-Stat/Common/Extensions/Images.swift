//
//  Images.swift
//  smm-printer-mac
//
//  Created by Сергей Бекезин on 04.06.2024.
//

import SwiftUI

// Some icons are used from SF symbols (available since iOS 13), some of them are available only in iOS 14.
// Therefore, icons available only in iOS 14 are added to assets with names as in SF symbols.
// In iOS 14 they will be initialized from SF symbols, and in iOS 13 from assets.
enum AppImage: String {
    
    // System Images
    case sfSidebarLeft = "sidebar.left"
    case sfPhoto = "photo"
    case sfPhotoOnRectangle = "photo.on.rectangle.angled"
    case sfCheckmarkFill = "checkmark.circle.fill"
    case sfGearshapeFill = "gearshape.fill"
    case sfTextformat = "textformat"
    case sfPrinterFill = "printer.fill"
    case sfPrinter = "printer"
    case sfSignpostRight = "signpost.right"
    case sfArrowLeftArrowRight = "arrow.left.arrow.right"
    case sfSignature = "signature"
    case sfChevronLeft = "chevron.left"
    case sfChevronDown = "chevron.down"
    case sfChevronUp = "chevron.up"
    case sfChevronRight = "chevron.right"
    case sfShare = "square.and.arrow.up"
    case sfTrash = "trash"
    case sfNosign = "nosign"
    case sfStar = "star.fill"
    case sfXmark = "xmark"
    
    case trialLogo
    
    var image: Image {
        return Image(rawValue)
    }
    
    var systemImage: Image {
        return Image(systemName: rawValue)
    }
    
}

