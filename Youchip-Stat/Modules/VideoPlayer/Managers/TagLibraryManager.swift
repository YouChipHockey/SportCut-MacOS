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
        if let first = standardCollections.first {
            applyStandardCollection(named: first.name)
        }
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleTagUpdated),
            name: .tagUpdated,
            object: nil
        )
        
        allTags = tags
        allTagGroups = tagGroups
        allLabelGroups = labelGroups
        allLabels = labels
        allTimeEvents = timeEvents
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
    
    private func loadAllUserCollections() {
        let userCollections = UserDefaults.standard.getCollectionBookmarks()
        
        for collection in userCollections {
            let collectionManager = CustomCollectionManager()
            if collectionManager.loadCollectionFromBookmarks(named: collection.name) {
                allTags.append(contentsOf: collectionManager.tags)
                allTagGroups.append(contentsOf: collectionManager.tagGroups)
                allLabelGroups.append(contentsOf: collectionManager.labelGroups)
                allLabels.append(contentsOf: collectionManager.labels)
                allTimeEvents.append(contentsOf: collectionManager.timeEvents)
            }
        }
        
        allTags = Array(Dictionary(grouping: allTags, by: { $0.id }).values.compactMap { $0.first })
        allTagGroups = Array(Dictionary(grouping: allTagGroups, by: { $0.id }).values.compactMap { $0.first })
        allLabelGroups = Array(Dictionary(grouping: allLabelGroups, by: { $0.id }).values.compactMap { $0.first })
        allLabels = Array(Dictionary(grouping: allLabels, by: { $0.id }).values.compactMap { $0.first })
        allTimeEvents = Array(Dictionary(grouping: allTimeEvents, by: { $0.id }).values.compactMap { $0.first })
    }
    
    func findOrCreateTimeEvent(id: String, name: String) -> TimeEvent {
        if let existingEvent = allTimeEvents.first(where: { $0.id == id }) {
            return existingEvent
        } else {
            let newEvent = TimeEvent(id: id, name: name)
            allTimeEvents.append(newEvent)
            return newEvent
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
        guard let originalID = notification.userInfo?["originalID"] as? String,
              let newID = notification.userInfo?["newID"] as? String else {
            return
        }
        
        for i in 0..<allTagGroups.count {
            if let tagIndex = allTagGroups[i].tags.firstIndex(where: { $0 == originalID }) {
                var updatedTags = allTagGroups[i].tags
                updatedTags[tagIndex] = newID
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
            if let first = standardCollections.first {
                applyStandardCollection(named: first.name)
            }
            currentCollectionType = .standard
            selectedTimeEvents.removeAll()
            refreshGlobalPools()
        }
    
    func applyHotkeysFromCurrentCollection() {
        HotKeyManager.shared.clearHotkeys()
        HotKeyManager.shared.registerHotkeys(from: tags, for: currentCollectionType)
    }
}
