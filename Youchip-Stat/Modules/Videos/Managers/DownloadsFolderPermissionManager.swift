//
//  DownloadsFolderPermissionManager.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 22.01.2026.
//

import Foundation
import AppKit

class DownloadsFolderPermissionManager: ObservableObject {
    
    static let shared = DownloadsFolderPermissionManager()
    
    @Published var hasDownloadsAccess: Bool = false
    @Published var showPermissionAlert: Bool = false
    
    private let downloadsBookmarkKey = "downloads_folder_bookmark"
    
    private init() {
        checkDownloadsAccess()
    }
    
    func checkDownloadsAccess() -> Bool {
        guard let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first else {
            hasDownloadsAccess = false
            return false
        }
        
        if let bookmarkData = UserDefaults.standard.data(forKey: downloadsBookmarkKey) {
            var isStale = false
            do {
                let url = try URL(resolvingBookmarkData: bookmarkData, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale)
                
                if !isStale {
                    _ = url.startAccessingSecurityScopedResource()
                    hasDownloadsAccess = true
                    return true
                }
            } catch {
            }
        }
        
        let testAccess = FileManager.default.isWritableFile(atPath: downloadsURL.path)
        hasDownloadsAccess = testAccess
        
        if testAccess {
            saveBookmark(for: downloadsURL)
        }
        
        return testAccess
    }
    
    @discardableResult
    func requestDownloadsAccess(completion: @escaping (Bool) -> Void) -> Bool {
        guard let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first else {
            completion(false)
            return false
        }
        
        if checkDownloadsAccess() {
            completion(true)
            return true
        }
        
        DispatchQueue.main.async { [weak self] in
            let panel = NSOpenPanel()
            panel.message = ^String.Titles.selectDownloadsFolderMessage
            panel.prompt = ^String.Titles.grantAccessButtonTitle
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.allowsMultipleSelection = false
            panel.canCreateDirectories = false
            panel.directoryURL = downloadsURL
            
            panel.begin { [weak self] response in
                guard let self = self else {
                    completion(false)
                    return
                }
                
                if response == .OK, let selectedURL = panel.url {
                    if selectedURL.path == downloadsURL.path {
                        self.saveBookmark(for: selectedURL)
                        self.hasDownloadsAccess = true
                        completion(true)
                    } else {
                        self.showPermissionAlert = true
                        completion(false)
                    }
                } else {
                    completion(false)
                }
            }
        }
        
        return false
    }
    
    private func saveBookmark(for url: URL) {
        do {
            let bookmarkData = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            UserDefaults.standard.set(bookmarkData, forKey: downloadsBookmarkKey)
        } catch {
        }
    }
    
    func openSystemPreferences() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        } else {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
        }
    }
    
    func resetPermissions() {
        UserDefaults.standard.removeObject(forKey: downloadsBookmarkKey)
        hasDownloadsAccess = false
    }
}
