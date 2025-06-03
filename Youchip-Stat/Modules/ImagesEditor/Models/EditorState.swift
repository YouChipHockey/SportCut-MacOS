//
//  EditorState.swift
//  smm-printer-mac
//
//  Created by Сергей Бекезин on 05.08.2024.
//

import Foundation
import SwiftUI

struct EditorState {
    
    var inputFile: URL
    var bufferFile: URL
    var image: NSImage
    var screenshotsFolder: URL
    
    var errorTitle = ""
    var infoTitle = ""
    
    var showPicker = false
    var shouldDissmis = false
    var showError = false
    var showInfo = false
    var showHUD = false
    var canRemoveLimit = true
    var showSubscriptionsBuySheet = false
    var showSubscriptionsSuccessSheet = false
    
}
