//
//  Youchip_StatApp.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 02.03.2025.
//

import SwiftUI
import Foundation
import Firebase
import FirebaseRemoteConfig

@main
struct Youchip_StatApp: App {
    
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var authManager = AuthManager()
    @State private var showTimeManipulationAlert = false
    @State private var showVersionOutdatedAlert = false
    
    init() {
        AppSetupManager.setup()
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(authManager)
                .onAppear {
                    if authManager.timeManipulationDetected {
                        showTimeManipulationAlert = true
                    } else {
                        checkAppVersion()
                    }
                }
                .alert("Предупреждение", isPresented: $showTimeManipulationAlert) {
                    Button(^String.Titles.fieldMapButtonOK) {
                        NSApplication.shared.terminate(nil)
                    }
                } message: {
                    Text("Пиратить и читерить - Плохо!!!!!")
                }
                .alert("Устаревшая версия", isPresented: $showVersionOutdatedAlert) {
                    Button(^String.Titles.fieldMapButtonOK) {
                        NSApplication.shared.terminate(nil)
                    }
                } message: {
                    Text("Ваша версия устарела, обновитесь до актуальной версии")
                }
        }
        .handlesExternalEvents(matching: [])
    }
    
    private func checkAppVersion() {
        let remoteConfig = RemoteConfig.remoteConfig()
        
        remoteConfig.fetch(withExpirationDuration: 0) { status, error in
            if status == .success {
                remoteConfig.activate { _, _ in
                    let requiredVersion = remoteConfig.configValue(forKey: "MajorVersion").stringValue
                    
                    if let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
                        if self.compareVersions(current: currentVersion, required: requiredVersion ?? "") == .orderedAscending {
                            DispatchQueue.main.async {
                                self.showVersionOutdatedAlert = true
                            }
                        }
                    }
                }
            }
        }
    }

    private func compareVersions(current: String, required: String) -> ComparisonResult {
        let currentComponents = current.components(separatedBy: ".").map { Int($0) ?? 0 }
        let requiredComponents = required.components(separatedBy: ".").map { Int($0) ?? 0 }
        
        if currentComponents.count > 0 && requiredComponents.count > 0 {
            if currentComponents[0] < requiredComponents[0] {
                return .orderedAscending
            } else if currentComponents[0] > requiredComponents[0] {
                return .orderedDescending
            }
        }
        
        if currentComponents.count > 1 && requiredComponents.count > 1 {
            if currentComponents[1] < requiredComponents[1] {
                return .orderedAscending
            } else if currentComponents[1] > requiredComponents[1] {
                return .orderedDescending
            }
        }
        
        return .orderedSame
    }
}

struct ContentView: View {
    @EnvironmentObject var authManager: AuthManager
    
    var body: some View {
        VideosView()
            .environmentObject(VideosViewModel())
            .environmentObject(authManager)
    }
}
