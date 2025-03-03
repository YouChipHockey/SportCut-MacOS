//
//  Youchip_StatApp.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 02.03.2025.
//

import SwiftUI

@main
struct Youchip_StatApp: App {
    
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
 
    init() {
        AppSetupManager.setup()
    }
    
    var body: some Scene {
        WindowGroup {
            VideosView()
                .environmentObject(VideosViewModel())
        }
        .handlesExternalEvents(matching: [])
    }
    
}
