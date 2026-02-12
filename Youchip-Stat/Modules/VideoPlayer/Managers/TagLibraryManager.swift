//
//  TagLibraryManager.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 6/19/25.
//

import SwiftUI
import AVKit
import Cocoa
import AVFoundation
import UniformTypeIdentifiers

struct StandardCollection {
    let name: String
    let tags: [Tag]
    let tagGroups: [TagGroup]
    let labelGroups: [LabelGroupData]
    let labels: [Label]
    let timeEvents: [TimeEvent]
}

class TagLibraryManager: ObservableObject {
    static let shared = TagLibraryManager()
    @Published var tags: [Tag] = []
    @Published var tagGroups: [TagGroup] = []
    @Published var labelGroups: [LabelGroupData] = []
    @Published var labels: [Label] = []
    @Published var timeEvents: [TimeEvent] = []
    @Published var allTags: [Tag] = []
    @Published var allTagGroups: [TagGroup] = []
    @Published var allLabelGroups: [LabelGroupData] = []
    @Published var allLabels: [Label] = []
    @Published var allTimeEvents: [TimeEvent] = []
    @Published var selectedTimeEvents: Set<String> = []
    
    private var defaultTags: [Tag] = []
    private var defaultTagGroups: [TagGroup] = []
    private var defaultLabelGroups: [LabelGroupData] = []
    private var defaultLabels: [Label] = []
    private var defaultTimeEvents: [TimeEvent] = []
    
    @Published var currentCollectionType: TagCollection = .standard
    
    @Published var standardCollections: [StandardCollection] = []
    @Published var selectedStandardCollectionName: String? = nil
    
    private init() {
        loadBaseCollections()
        applyDefaultCollection()
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleTagUpdated),
            name: .tagUpdated,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleCollectionDataChanged),
            name: .collectionDataChanged,
            object: nil
        )
        
        allTags = tags
        allTagGroups = tagGroups
        allLabelGroups = labelGroups
        allLabels = labels
        allTimeEvents = timeEvents
        loadAllUserCollections()
    }
    
    @objc private func handleCollectionDataChanged() {
        // Clear cache and reload all user collections when collections are updated
        loadedCollectionsCache.removeAll()
        // Reload all user collections asynchronously
        loadAllUserCollections()
    }
        
    private func getSystemLanguage() -> String {
        let preferredLanguage = Locale.preferredLanguages.first ?? "en"
        if preferredLanguage.hasPrefix("ru") {
            return "ru"
        } else if preferredLanguage.hasPrefix("en") {
            return "en"
        } else if preferredLanguage.hasPrefix("uz") {
            return "ru"
        } else {
            return "en"
        }
    }
    
    private func getCollectionFileURL(for resourceName: String, collectionName: String) -> URL? {
        let fullResourceName = "\(resourceName)(\(collectionName))"
        return Bundle.main.url(forResource: fullResourceName, withExtension: "json")
    }
    
    private func loadBaseCollections() {
        guard let namesUrl = Bundle.main.url(forResource: "names", withExtension: "json") else { return }
        
        guard let languageCollectionsData: LanguageCollectionsData = loadJSON(url: namesUrl) else { return }
        
        let currentLanguage = getSystemLanguage()
        
        guard let currentLanguageCollection = languageCollectionsData.collections.first(where: { $0.language == currentLanguage }) else {
            guard let fallbackCollection = languageCollectionsData.collections.first(where: { $0.language == "en" }) else { return }
            loadCollectionsForNames(fallbackCollection.names)
            return
        }
        
        loadCollectionsForNames(currentLanguageCollection.names)
    }
    
    private func loadCollectionsForNames(_ names: [String]) {
        for name in names {
            let tagsURL = getCollectionFileURL(for: "tags", collectionName: name)
            let tagsGroupsURL = getCollectionFileURL(for: "tagsGroups", collectionName: name)
            let labelsGroupsURL = getCollectionFileURL(for: "labelsGroups", collectionName: name)
            let labelsURL = getCollectionFileURL(for: "labels", collectionName: name)
            let timeEventsURL = getCollectionFileURL(for: "timeEvents", collectionName: name)
            
            var tags: [Tag] = []
            var tagGroups: [TagGroup] = []
            var labelGroups: [LabelGroupData] = []
            var labels: [Label] = []
            var timeEvents: [TimeEvent] = []
            
            if let tagsURL = tagsURL {
                if let loadedTags: TagsData = loadJSON(url: tagsURL) {
                    tags = loadedTags.tags
                }
            }
            
            if let tagsGroupsURL = tagsGroupsURL {
                if let loadedTags: TagGroupsData = loadJSON(url: tagsGroupsURL) {
                    tagGroups = loadedTags.tagGroups
                }
            }
            
            if let labelsGroupsURL = labelsGroupsURL {
                if let loadedTags: LabelGroupsData = loadJSON(url: labelsGroupsURL) {
                    labelGroups = loadedTags.labelGroups
                }
            }
            
            if let labelsURL = labelsURL {
                if let loadedTags: LabelsData = loadJSON(url: labelsURL) {
                    labels = loadedTags.labels
                }
            }
            
            if let timeEventsURL = timeEventsURL {
                if let loadedTags: TimeEventsData = loadJSON(url: timeEventsURL) {
                    timeEvents = loadedTags.events
                }
            }
            
            let displayName = name
            let collection = StandardCollection(
                name: displayName,
                tags: tags,
                tagGroups: tagGroups,
                labelGroups: labelGroups,
                labels: labels,
                timeEvents: timeEvents
            )
            standardCollections.append(collection)
        }
    }
    
    func applyStandardCollection(named name: String) {
        guard let collection = standardCollections.first(where: { $0.name == name }) else { return }
        UserDefaults.standard.set(name, forKey: UserDefaults.Keys.lastSelectedCollection)
        tags = collection.tags
        tagGroups = collection.tagGroups
        labelGroups = collection.labelGroups
        labels = collection.labels
        timeEvents = collection.timeEvents
        currentCollectionType = .standard
        selectedStandardCollectionName = name
        selectedTimeEvents.removeAll()
        refreshGlobalPools()
        applyHotkeysFromCurrentCollection()
    }
    
    func findTagById(_ id: String) -> Tag? {
        return allTags.first(where: { $0.id == id })
    }
    
    func findLabelById(_ id: String) -> Label? {
        return allLabels.first(where: { $0.id == id })
    }
    
    func findTagGroupForTag(_ tagID: String) -> TagGroup? {
        return allTagGroups.first { group in
            group.tags.contains(tagID)
        }
    }
        
    func findLabelsForTag(_ tag: Tag) -> [Label] {
        let labelGroupIds = tag.lablesGroup
        let relevantLabelIds = allLabelGroups.filter { labelGroupIds.contains($0.id) }
            .flatMap { $0.lables }
        return allLabels.filter { label in relevantLabelIds.contains(label.id) }
    }
    
    // Cache for loaded collections to avoid reloading
    private var loadedCollectionsCache: [String: (tags: [Tag], tagGroups: [TagGroup], labelGroups: [LabelGroupData], labels: [Label], timeEvents: [TimeEvent])] = [:]
    private let collectionLoadingQueue = DispatchQueue(label: "com.youchip.collectionLoading", attributes: .concurrent)
    
    private func loadAllUserCollections() {
        // Load asynchronously in background to avoid blocking main thread
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            let userCollections = UserDefaults.standard.getCollectionBookmarks()
            print("📚 TagLibraryManager: Loading \(userCollections.count) user collections asynchronously")
            
            // Use concurrent queue for parallel loading
            let group = DispatchGroup()
            var loadedData: [(tags: [Tag], tagGroups: [TagGroup], labelGroups: [LabelGroupData], labels: [Label], timeEvents: [TimeEvent])] = []
            let lock = NSLock()
            
            for collection in userCollections {
                group.enter()
                self.collectionLoadingQueue.async {
                    print("📚 TagLibraryManager: Loading collection '\(collection.name)' (id: \(collection.id))")
                    let collectionManager = CustomCollectionManager()
                    if collectionManager.loadCollectionFromBookmarks(named: collection.name) {
                        print("✅ TagLibraryManager: Successfully loaded collection '\(collection.name)' - tags: \(collectionManager.tags.count), tagGroups: \(collectionManager.tagGroups.count)")
                        
                        // Cache the loaded collection
                        lock.lock()
                        self.loadedCollectionsCache[collection.name] = (
                            tags: collectionManager.tags,
                            tagGroups: collectionManager.tagGroups,
                            labelGroups: collectionManager.labelGroups,
                            labels: collectionManager.labels,
                            timeEvents: collectionManager.timeEvents
                        )
                        loadedData.append((
                            tags: collectionManager.tags,
                            tagGroups: collectionManager.tagGroups,
                            labelGroups: collectionManager.labelGroups,
                            labels: collectionManager.labels,
                            timeEvents: collectionManager.timeEvents
                        ))
                        lock.unlock()
                    } else {
                        print("❌ TagLibraryManager: Failed to load collection '\(collection.name)'")
                    }
                    group.leave()
                }
            }
            
            // Wait for all collections to load
            group.wait()
            
            // Add standard collections data
            for collection in self.standardCollections {
                loadedData.append((
                    tags: collection.tags,
                    tagGroups: collection.tagGroups,
                    labelGroups: collection.labelGroups,
                    labels: collection.labels,
                    timeEvents: collection.timeEvents
                ))
            }
            
            // Merge all data
            var mergedTags: [Tag] = []
            var mergedTagGroups: [TagGroup] = []
            var mergedLabelGroups: [LabelGroupData] = []
            var mergedLabels: [Label] = []
            var mergedTimeEvents: [TimeEvent] = []
            
            for data in loadedData {
                mergedTags.append(contentsOf: data.tags)
                mergedTagGroups.append(contentsOf: data.tagGroups)
                mergedLabelGroups.append(contentsOf: data.labelGroups)
                mergedLabels.append(contentsOf: data.labels)
                mergedTimeEvents.append(contentsOf: data.timeEvents)
            }
            
            // Deduplicate
            let finalTags = Array(Dictionary(grouping: mergedTags, by: { $0.id }).values.compactMap { $0.first })
            let finalTagGroups = Array(Dictionary(grouping: mergedTagGroups, by: { $0.id }).values.compactMap { $0.first })
            let finalLabelGroups = Array(Dictionary(grouping: mergedLabelGroups, by: { $0.id }).values.compactMap { $0.first })
            let finalLabels = Array(Dictionary(grouping: mergedLabels, by: { $0.id }).values.compactMap { $0.first })
            let finalTimeEvents = Array(Dictionary(grouping: mergedTimeEvents, by: { $0.id }).values.compactMap { $0.first })
            
            // Update UI on main thread
            DispatchQueue.main.async {
                self.allTags = finalTags
                self.allTagGroups = finalTagGroups
                self.allLabelGroups = finalLabelGroups
                self.allLabels = finalLabels
                self.allTimeEvents = finalTimeEvents
                print("✅ TagLibraryManager: Finished loading all collections - total tags: \(finalTags.count), tagGroups: \(finalTagGroups.count)")
            }
        }
    }
    
    /// Get cached collection data if available, otherwise load it
    func getCollectionData(for collectionName: String) -> (tags: [Tag], tagGroups: [TagGroup], labelGroups: [LabelGroupData], labels: [Label], timeEvents: [TimeEvent])? {
        if let cached = loadedCollectionsCache[collectionName] {
            return cached
        }
        
        // Load synchronously if not cached (should be rare)
        let collectionManager = CustomCollectionManager()
        if collectionManager.loadCollectionFromBookmarks(named: collectionName) {
            let data = (
                tags: collectionManager.tags,
                tagGroups: collectionManager.tagGroups,
                labelGroups: collectionManager.labelGroups,
                labels: collectionManager.labels,
                timeEvents: collectionManager.timeEvents
            )
            loadedCollectionsCache[collectionName] = data
            return data
        }
        
        return nil
    }
    
    func findOrCreateTimeEvent(id: String, name: String, shouldCreate: Bool = true) -> TimeEvent? {
        if let existingEvent = allTimeEvents.first(where: { $0.id == id }) {
            return existingEvent
        } else if shouldCreate {
            let newEvent = TimeEvent(id: id, name: name)
            allTimeEvents.append(newEvent)
            return newEvent
        } else {
            return nil
        }
    }
    
    
    func toggleTimeEvent(id: String) {
        if selectedTimeEvents.contains(id) {
            selectedTimeEvents.remove(id)
        } else {
            selectedTimeEvents.insert(id)
        }
    }
    
    @objc private func handleTagUpdated(_ notification: Notification) {
        guard let tagId = notification.userInfo?["tagId"] as? String else { return }
        
        for i in 0..<allTagGroups.count {
            if let tagIndex = allTagGroups[i].tags.firstIndex(where: { $0 == tagId }) {
                var updatedTags = allTagGroups[i].tags
                updatedTags[tagIndex] = tagId
                allTagGroups[i] = TagGroup(
                    id: allTagGroups[i].id,
                    name: allTagGroups[i].name,
                    tags: updatedTags
                )
            }
        }
        
        refreshGlobalPools()
    }
    
    func refreshGlobalPools() {
        let standardTags = tags
        let standardTagGroups = tagGroups
        let standardLabelGroups = labelGroups
        let standardLabels = labels
        let standardTimeEvents = timeEvents
        
        allTags = standardTags
        allTagGroups = standardTagGroups
        allLabelGroups = standardLabelGroups
        allLabels = standardLabels
        allTimeEvents = standardTimeEvents
        loadAllUserCollections()
        applyHotkeysFromCurrentCollection()
    }
    
    func restoreDefaultData() {
        applyDefaultCollection()
        currentCollectionType = .standard
        selectedTimeEvents.removeAll()
        refreshGlobalPools()
    }

    func applyHotkeysFromCurrentCollection() {
        HotKeyManager.shared.clearHotkeys()
        HotKeyManager.shared.registerHotkeys(from: tags, for: currentCollectionType)
    }
    
    func applyDefaultCollection() {
        let lastSelectedCollectionName = UserDefaults.standard.string(forKey: UserDefaults.Keys.lastSelectedCollection)
        let collectionManager = CustomCollectionManager()
        if let lastSelectedCollectionName, collectionManager.loadCollectionFromBookmarks(named: lastSelectedCollectionName) {
            tags = collectionManager.tags
            tagGroups = collectionManager.tagGroups
            labelGroups = collectionManager.labelGroups
            labels = collectionManager.labels
            timeEvents = collectionManager.timeEvents
            selectedTimeEvents.removeAll()
            currentCollectionType = .user(name: lastSelectedCollectionName)
            HotKeyManager.shared.clearHotkeys()
            HotKeyManager.shared.registerHotkeys(from: tags, for: .user(name: lastSelectedCollectionName))
            selectedStandardCollectionName = lastSelectedCollectionName
        } else if let standardCollection =
                    standardCollections.first(where: { $0.name == lastSelectedCollectionName }) ??
                    standardCollections.first
        {
            applyStandardCollection(named: standardCollection.name)
            selectedStandardCollectionName = standardCollection.name
        }
    }
}
