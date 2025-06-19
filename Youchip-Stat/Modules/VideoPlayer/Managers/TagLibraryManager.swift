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
    
    private init() {
        if let loadedTags: TagsData = loadJSON(filename: "tags.json") {
            self.tags = loadedTags.tags
            self.defaultTags = loadedTags.tags
        }
        if let loadedTagGroups: TagGroupsData = loadJSON(filename: "tagsGroups.json") {
            self.tagGroups = loadedTagGroups.tagGroups
            self.defaultTagGroups = loadedTagGroups.tagGroups
        }
        if let loadedLabelGroups: LabelGroupsData = loadJSON(filename: "labelsGroups.json") {
            self.labelGroups = loadedLabelGroups.labelGroups
            self.defaultLabelGroups = loadedLabelGroups.labelGroups
        }
        if let loadedLabels: LabelsData = loadJSON(filename: "labels.json") {
            self.labels = loadedLabels.labels
            self.defaultLabels = loadedLabels.labels
        }
        if let loadedTimeEvents: TimeEventsData = loadJSON(filename: "timeEvents.json") {
            self.timeEvents = loadedTimeEvents.events
            self.defaultTimeEvents = loadedTimeEvents.events
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
        tags = defaultTags
        tagGroups = defaultTagGroups
        labelGroups = defaultLabelGroups
        labels = defaultLabels
        timeEvents = defaultTimeEvents
        currentCollectionType = .standard
        
        selectedTimeEvents.removeAll()
        refreshGlobalPools()
    }
    
    func applyHotkeysFromCurrentCollection() {
        HotKeyManager.shared.clearHotkeys()
        HotKeyManager.shared.registerHotkeys(from: tags, for: currentCollectionType)
    }
}
