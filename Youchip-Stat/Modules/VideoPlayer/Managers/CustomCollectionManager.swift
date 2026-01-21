//
//  CustomCollectionManager.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 06.05.2025.
//

import SwiftUI
import Foundation
import UniformTypeIdentifiers

class CustomCollectionManager: ObservableObject {
    
    var changedTagIds: [String] = []
    @Published var playField: PlayField?
    @Published var tagGroups: [TagGroup] = []
    @Published var tags: [Tag] = []
    @Published var labelGroups: [LabelGroupData] = []
    @Published var labels: [Label] = []
    @Published var timeEvents: [TimeEvent] = []
    @Published var collectionName: String = ^String.Titles.myCollection
    @Published var collectionID: String = UUID().uuidString
    @Published var isEditingExisting: Bool = false
    @Published var allCollections: [StandardCollection] = []
    var originalName: String = ""
    
    init() {}
    
    init(withBookmark bookmark: CollectionBookmark) {
        self.isEditingExisting = true
        self.originalName = bookmark.name
        self.collectionName = bookmark.name
        self.collectionID = bookmark.id
        loadCollectionFromBookmarks(named: bookmark.name)
        loadAllCollections()
    }
    
    func renameTagGroup(id: String, newName: String) {
        if let index = tagGroups.firstIndex(where: { $0.id == id }) {
            tagGroups[index] = TagGroup(
                id: id,
                name: newName,
                tags: tagGroups[index].tags
            )
            objectWillChange.send()
        }
    }
    
    func renameLabelGroup(id: String, newName: String) {
        if let index = labelGroups.firstIndex(where: { $0.id == id }) {
            labelGroups[index] = LabelGroupData(
                id: id,
                name: newName,
                lables: labelGroups[index].lables
            )
            objectWillChange.send()
        }
    }
    
    func renameTimeEvent(id: String, newName: String) {
        if let index = timeEvents.firstIndex(where: { $0.id == id }) {
            timeEvents[index] = TimeEvent(
                id: id,
                name: newName
            )
            objectWillChange.send()
        }
    }
    
    func updateLabel(id: String, name: String, description: String) {
        if let index = labels.firstIndex(where: { $0.id == id }) {
            labels[index] = Label(
                id: id,
                name: name,
                description: description
            )
            objectWillChange.send()
        }
    }
    
    func updateTimeEvent(id: String, newName: String) {
        if let index = timeEvents.firstIndex(where: { $0.id == id }) {
            timeEvents[index] = TimeEvent(
                id: id,
                name: newName
            )
            objectWillChange.send()
        }
    }
    
    func createTagGroup(name: String) -> TagGroup {
        let newGroup = TagGroup(id: UUID().uuidString, name: name, tags: [])
        tagGroups.append(newGroup)
        return newGroup
    }
    
    func createTag(name: String, description: String, color: String,
                   defaultTimeBefore: Double, defaultTimeAfter: Double,
                   inGroup groupID: String, hotkey: String? = nil, isInterval: Bool) -> Tag {
        if let hotkey = hotkey, !hotkey.isEmpty {
            if tags.contains(where: { $0.hotkey == hotkey }) {
                return createTagWithValidatedHotkey(name: name, description: description, color: color,
                                                    defaultTimeBefore: defaultTimeBefore,
                                                    defaultTimeAfter: defaultTimeAfter,
                                                    inGroup: groupID, hotkey: nil, isInterval: isInterval)
            }
        }
        
        return createTagWithValidatedHotkey(name: name, description: description, color: color,
                                            defaultTimeBefore: defaultTimeBefore,
                                            defaultTimeAfter: defaultTimeAfter,
                                            inGroup: groupID, hotkey: hotkey, isInterval: isInterval)
    }
    
    func deleteTag(id: String) {
        for index in tagGroups.indices {
            tagGroups[index].tags.removeAll { $0 == id }
        }
        for tagIndex in tags.indices {
            if tags[tagIndex].id == id {
                tags[tagIndex].lablesGroup = []
                tags[tagIndex].labelHotkeys = [:]
            }
        }
        
        tags.removeAll { $0.id == id }
        objectWillChange.send()
    }
    
    func deleteTagGroup(id: String) {
        if let group = tagGroups.first(where: { $0.id == id }) {
            let tagsToRemove = group.tags.filter { tagId in
                !tagGroups.contains { otherGroup in
                    otherGroup.id != id && otherGroup.tags.contains(tagId)
                }
            }
            for tagId in tagsToRemove {
                deleteTag(id: tagId)
            }
        }
        
        tagGroups.removeAll { $0.id == id }
        objectWillChange.send()
    }
    
    func deleteLabel(id: String) {
        for index in labelGroups.indices {
            labelGroups[index].lables.removeAll { $0 == id }
        }
        for tagIndex in tags.indices {
            tags[tagIndex].labelHotkeys?.removeValue(forKey: id)
        }
        labels.removeAll { $0.id == id }
        objectWillChange.send()
    }
    
    func deleteTimeEvent(id: String) {
        timeEvents.removeAll { $0.id == id }
        objectWillChange.send()
    }
    
    func deleteLabelGroup(id: String) {
        if let group = labelGroups.first(where: { $0.id == id }) {
            let labelsToRemove = group.lables.filter { labelId in
                !labelGroups.contains { otherGroup in
                    otherGroup.id != id && otherGroup.lables.contains(labelId)
                }
            }
            for labelId in labelsToRemove {
                deleteLabel(id: labelId)
            }
            for tagIndex in tags.indices {
                tags[tagIndex].lablesGroup.removeAll { $0 == id }
            }
        }
        labelGroups.removeAll { $0.id == id }
        objectWillChange.send()
    }
    
    private func createTagWithValidatedHotkey(name: String, description: String, color: String,
                                              defaultTimeBefore: Double, defaultTimeAfter: Double,
                                              inGroup groupID: String, hotkey: String?, isInterval: Bool?) -> Tag {
        let id = UUID().uuidString
        let newTag = Tag(
            id: id,
            primaryID: id,
            name: name,
            description: description,
            color: color,
            defaultTimeBefore: defaultTimeBefore,
            defaultTimeAfter: defaultTimeAfter,
            collection: collectionName,
            lablesGroup: [],
            hotkey: hotkey,
            labelHotkeys: [:],
            isInterval: isInterval
        )
        
        tags.append(newTag)
        if let index = tagGroups.firstIndex(where: { $0.id == groupID }) {
            var updatedGroup = tagGroups[index]
            var updatedTags = updatedGroup.tags
            updatedTags.append(newTag.id)
            tagGroups[index] = TagGroup(
                id: updatedGroup.id,
                name: updatedGroup.name,
                tags: updatedTags
            )
        }
        
        return newTag
    }
    
    func createLabelGroup(name: String) -> LabelGroupData {
        let newGroup = LabelGroupData(id: UUID().uuidString, name: name, lables: [])
        labelGroups.append(newGroup)
        return newGroup
    }
    
    func createLabel(name: String, description: String, inGroup groupID: String) -> Label {
        let newLabel = Label(
            id: UUID().uuidString,
            name: name,
            description: description
        )
        
        labels.append(newLabel)
        if let index = labelGroups.firstIndex(where: { $0.id == groupID }) {
            var updatedGroup = labelGroups[index]
            var updatedLabels = updatedGroup.lables
            updatedLabels.append(newLabel.id)
            labelGroups[index] = LabelGroupData(
                id: updatedGroup.id,
                name: updatedGroup.name,
                lables: updatedLabels
            )
        }
        
        return newLabel
    }
    func updateTagLabelGroups(tagID: String, labelGroupIDs: [String]) {
        if let index = tags.firstIndex(where: { $0.id == tagID }) {
            tags[index] = Tag(
                id: tags[index].id,
                primaryID: tags[index].primaryID,
                name: tags[index].name,
                description: tags[index].description,
                color: tags[index].color,
                defaultTimeBefore: tags[index].defaultTimeBefore,
                defaultTimeAfter: tags[index].defaultTimeAfter,
                collection: tags[index].collection,
                lablesGroup: labelGroupIDs,
                hotkey: tags[index].hotkey,
                labelHotkeys: tags[index].labelHotkeys
            )
        }
    }
    
    func addTagToGroup(tagID: String, groupID: String) {
        if let index = tagGroups.firstIndex(where: { $0.id == groupID }) {
            var updatedGroup = tagGroups[index]
            if !updatedGroup.tags.contains(tagID) {
                var updatedTags = updatedGroup.tags
                updatedTags.append(tagID)
                tagGroups[index] = TagGroup(
                    id: updatedGroup.id,
                    name: updatedGroup.name,
                    tags: updatedTags
                )
            }
        }
    }
    
    func removeTagFromGroup(tagID: String, groupID: String) {
        if let index = tagGroups.firstIndex(where: { $0.id == groupID }) {
            var updatedGroup = tagGroups[index]
            var updatedTags = updatedGroup.tags
            updatedTags.removeAll(where: { $0 == tagID })
            tagGroups[index] = TagGroup(
                id: updatedGroup.id,
                name: updatedGroup.name,
                tags: updatedTags
            )
        }
    }
    
    func saveCollectionToFiles() -> Bool {
        collectionName = collectionName.trimmingCharacters(in: .whitespacesAndNewlines)
        if collectionName == originalName || collectionName.isEmpty {
            collectionName = originalName
        } else {
            collectionName = ensureUniqueCollectionName(collectionName, collectionID: collectionID)
        }
        
        do {
            let tagGroupsData = TagGroupsData(tagGroups: tagGroups)
            let tagsData = TagsData(tags: tags)
            let labelGroupsData = LabelGroupsData(labelGroups: labelGroups)
            let labelsData = LabelsData(labels: labels)
            let timeEventsData = TimeEventsData(events: timeEvents)
            
            let urlString = URLConstants.getCollecitonFolderStringUrl(with: collectionID)
            let collectionsFolderUrl = URL.appDocumentsDirectory
                .appendingPathComponent(urlString, isDirectory: true)
            
            let fileManager = FileManager.default
            if !fileManager.fileExists(atPath: collectionsFolderUrl.path) {
                try fileManager.createDirectory(at: collectionsFolderUrl, withIntermediateDirectories: true)
            }
            
            let tagGroupsURL = collectionsFolderUrl.appendingPathComponent("tagGroups.json")
            let tagsURL = collectionsFolderUrl.appendingPathComponent("tags.json")
            let labelGroupsURL = collectionsFolderUrl.appendingPathComponent("labelGroups.json")
            let labelsURL = collectionsFolderUrl.appendingPathComponent("labels.json")
            let timeEventsURL = collectionsFolderUrl.appendingPathComponent("timeEvents.json")
            let playFieldURL = collectionsFolderUrl.appendingPathComponent("playField.json")
            
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            
            let tagGroupsJSON = try encoder.encode(tagGroupsData)
            try tagGroupsJSON.write(to: tagGroupsURL)
            let tagGroupsBookmark = tagGroupsURL.makeBookmark() ?? Data()
            
            let tagsJSON = try encoder.encode(tagsData)
            try tagsJSON.write(to: tagsURL)
            let tagsBookmark = tagsURL.makeBookmark() ?? Data()
            
            let labelGroupsJSON = try encoder.encode(labelGroupsData)
            try labelGroupsJSON.write(to: labelGroupsURL)
            let labelGroupsBookmark = labelGroupsURL.makeBookmark() ?? Data()
            
            let labelsJSON = try encoder.encode(labelsData)
            try labelsJSON.write(to: labelsURL)
            let labelsBookmark = labelsURL.makeBookmark() ?? Data()
            
            let timeEventsJSON = try encoder.encode(timeEventsData)
            try timeEventsJSON.write(to: timeEventsURL)
            let timeEventsBookmark = timeEventsURL.makeBookmark() ?? Data()
            
            var playFieldBookmark = Data()
            if let field = playField {
                let playFieldJSON = try encoder.encode(field)
                try playFieldJSON.write(to: playFieldURL)
                playFieldBookmark = playFieldURL.makeBookmark() ?? Data()
            }
            
            let collectionBookmark = CollectionBookmark(
                id: collectionID,
                name: collectionName,
                tagGroupsBookmark: tagGroupsBookmark,
                tagsBookmark: tagsBookmark,
                labelGroupsBookmark: labelGroupsBookmark,
                labelsBookmark: labelsBookmark,
                timeEventsBookmark: timeEventsBookmark,
                playFieldBookmark: playFieldBookmark
            )
            
            UserDefaults.standard.saveCollectionBookmark(collectionBookmark)
            originalName = collectionName
            if !isEditingExisting {
                isEditingExisting = true
            }
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .collectionDataChanged, object: nil)
            }
            
            for tagId in changedTagIds {
                NotificationCenter.default.post(
                    name: .tagUpdated,
                    object: nil,
                    userInfo: ["tagId": tagId]
                )
            }
            changedTagIds.removeAll()
            
            return true
        } catch {
            print("SAVE ERROR:", error.localizedDescription)
            return false
        }
    }
    
    func ensureUniqueCollectionName(_ baseName: String, collectionID: String) -> String {
        let existingNames = UserDefaults.standard
            .getCollectionBookmarks()
            .filter { $0.id != collectionID }
            .map(\.name)
        if (isEditingExisting && baseName == originalName) || !existingNames.contains(baseName) {
            return baseName
        }
        var counter = 1
        var newName = "\(baseName) (\(counter))"
        
        while existingNames.contains(newName) {
            counter += 1
            newName = "\(baseName) (\(counter))"
        }
        
        return newName
    }
    
    @discardableResult
    func loadCollectionFromBookmarks(named collectionName: String) -> Bool {
        guard let bookmark = UserDefaults.standard.getCollectionBookmarks()
            .first(where: { $0.name == collectionName }) else {
            return false
        }
        
        do {
            var isStale = false
            var urls: [URL] = []
            var accessFlags: [Bool] = []
            
            do {
                let tagGroupsURL = try URL(resolvingBookmarkData: bookmark.tagGroupsBookmark,
                                           options: .withSecurityScope,
                                           relativeTo: nil,
                                           bookmarkDataIsStale: &isStale)
                urls.append(tagGroupsURL)
                let accessFlag = tagGroupsURL.startAccessingSecurityScopedResource()
                accessFlags.append(accessFlag)
            } catch {
                return false
            }
            
            do {
                let tagsURL = try URL(resolvingBookmarkData: bookmark.tagsBookmark,
                                      options: .withSecurityScope,
                                      relativeTo: nil,
                                      bookmarkDataIsStale: &isStale)
                urls.append(tagsURL)
                let accessFlag = tagsURL.startAccessingSecurityScopedResource()
                accessFlags.append(accessFlag)
            } catch {
                stopAccessingResources(urls: urls)
                return false
            }
            
            do {
                let labelGroupsURL = try URL(resolvingBookmarkData: bookmark.labelGroupsBookmark,
                                             options: .withSecurityScope,
                                             relativeTo: nil,
                                             bookmarkDataIsStale: &isStale)
                urls.append(labelGroupsURL)
                let accessFlag = labelGroupsURL.startAccessingSecurityScopedResource()
                accessFlags.append(accessFlag)
            } catch {
                stopAccessingResources(urls: urls)
                return false
            }
            
            do {
                let labelsURL = try URL(resolvingBookmarkData: bookmark.labelsBookmark,
                                        options: .withSecurityScope,
                                        relativeTo: nil,
                                        bookmarkDataIsStale: &isStale)
                urls.append(labelsURL)
                let accessFlag = labelsURL.startAccessingSecurityScopedResource()
                accessFlags.append(accessFlag)
            } catch {
                stopAccessingResources(urls: urls)
                return false
            }
            
            do {
                if bookmark.timeEventsBookmark.isEmpty {
                } else {
                    let timeEventsURL = try URL(resolvingBookmarkData: bookmark.timeEventsBookmark,
                                                options: .withSecurityScope,
                                                relativeTo: nil,
                                                bookmarkDataIsStale: &isStale)
                    urls.append(timeEventsURL)
                    let accessFlag = timeEventsURL.startAccessingSecurityScopedResource()
                    accessFlags.append(accessFlag)
                }
            } catch {
                stopAccessingResources(urls: urls)
            }
            
            var playFieldURL: URL? = nil
            do {
                if let playFieldBookmark = bookmark.playFieldBookmark {
                    if !playFieldBookmark.isEmpty {
                        playFieldURL = try URL(resolvingBookmarkData: playFieldBookmark,
                                               options: .withSecurityScope,
                                               relativeTo: nil,
                                               bookmarkDataIsStale: &isStale)
                        urls.append(playFieldURL!)
                        let accessFlag = playFieldURL!.startAccessingSecurityScopedResource()
                        accessFlags.append(accessFlag)
                    }
                }
            } catch {
                stopAccessingResources(urls: urls)
            }
            
            if urls.count < 4 || accessFlags.contains(false) {
                stopAccessingResources(urls: urls)
                return false
            }
            
            defer {
                stopAccessingResources(urls: urls)
            }
            
            let tagGroupsURL = urls[0]
            let tagsURL = urls[1]
            let labelGroupsURL = urls[2]
            let labelsURL = urls[3]
            
            let decoder = JSONDecoder()
            
            do {
                let tagGroupsData = try Data(contentsOf: tagGroupsURL)
                let tagGroupsContainer = try decoder.decode(TagGroupsData.self, from: tagGroupsData)
                self.tagGroups = tagGroupsContainer.tagGroups
            } catch {
                return false
            }
            
            do {
                let tagsData = try Data(contentsOf: tagsURL)
                let tagsContainer = try decoder.decode(TagsData.self, from: tagsData)
                self.tags = tagsContainer.tags
            } catch {
                return false
            }
            
            do {
                let labelGroupsData = try Data(contentsOf: labelGroupsURL)
                let labelGroupsContainer = try decoder.decode(LabelGroupsData.self, from: labelGroupsData)
                self.labelGroups = labelGroupsContainer.labelGroups
            } catch {
                return false
            }
            
            do {
                let labelsData = try Data(contentsOf: labelsURL)
                let labelsContainer = try decoder.decode(LabelsData.self, from: labelsData)
                self.labels = labelsContainer.labels
            } catch {
                return false
            }
            if urls.count > 4 {
                let timeEventsURL = urls[4]
                do {
                    let timeEventsData = try Data(contentsOf: timeEventsURL)
                    let timeEventsContainer = try decoder.decode(TimeEventsData.self, from: timeEventsData)
                    self.timeEvents = timeEventsContainer.events
                } catch {
                    self.timeEvents = []
                }
            } else {
                self.timeEvents = []
            }
            
            if let fieldURL = playFieldURL {
                do {
                    let fieldData = try Data(contentsOf: fieldURL)
                    self.playField = try decoder.decode(PlayField.self, from: fieldData)
                } catch {
                    self.playField = nil
                }
            } else {
                self.playField = nil
            }
            
            self.collectionName = collectionName
            if isStale {
                refreshBookmark(collection: collectionName, urls: urls)
            }
            
            return true
        } catch {
            return false
        }
    }
    
    private func loadAllCollections() {
        let allBookmarks = UserDefaults.standard.getCollectionBookmarks()
        
    }
    
    func updateTagMapEnabled(id: String, mapEnabled: Bool) -> Bool {
        if let index = tags.firstIndex(where: { $0.id == id }) {
            let updatedTag = Tag(
                id: tags[index].id,
                primaryID: tags[index].primaryID,
                name: tags[index].name,
                description: tags[index].description,
                color: tags[index].color,
                defaultTimeBefore: tags[index].defaultTimeBefore,
                defaultTimeAfter: tags[index].defaultTimeAfter,
                collection: tags[index].collection,
                lablesGroup: tags[index].lablesGroup,
                hotkey: tags[index].hotkey,
                labelHotkeys: tags[index].labelHotkeys,
                mapEnabled: mapEnabled
            )
            
            tags[index] = updatedTag
            objectWillChange.send()
            return true
        }
        return false
    }
    
    func savePlayFieldForCollection() -> Bool {
        guard let playField = playField else { return true }
        
        do {
            let fileManager = FileManager.default
            let playFieldsFolder = URL.appDocumentsDirectory
                .appendingPathComponent("YouChip-Stat/PlayFields", isDirectory: true)
                .fixedFile()
            
            if !fileManager.fileExists(atPath: playFieldsFolder.path) {
                try fileManager.createDirectory(at: playFieldsFolder, withIntermediateDirectories: true)
            }
            
            let playFieldDataPath = playFieldsFolder.appendingPathComponent("\(collectionName).json")
            
            let updatedField = PlayField(
                id: playField.id,
                name: playField.name,
                imagePath: "",
                width: playField.width,
                height: playField.height
            )
            
            let data = try JSONEncoder().encode(updatedField)
            try data.write(to: playFieldDataPath)
            
            return true
        } catch {
            return false
        }
    }

    func loadPlayFieldForCollection() {
        let fileManager = FileManager.default
        let playFieldsFolder = URL.appDocumentsDirectory
            .appendingPathComponent("YouChip-Stat/PlayFields", isDirectory: true)
            .fixedFile()
        
        let newPlayFieldDataPath = playFieldsFolder.appendingPathComponent("\(collectionName).json")
        
        if fileManager.fileExists(atPath: newPlayFieldDataPath.path),
           let data = try? Data(contentsOf: newPlayFieldDataPath) {
            if var field = try? JSONDecoder().decode(PlayField.self, from: data) {
                field.imagePath = "\(collectionName).png"
                playField = field
                return
            }
        }
        
        let oldPlayFieldDataPath = playFieldsFolder
            .appendingPathComponent("\(collectionName)/field.json")
        
        if fileManager.fileExists(atPath: oldPlayFieldDataPath.path),
           let data = try? Data(contentsOf: oldPlayFieldDataPath) {
            if var field = try? JSONDecoder().decode(PlayField.self, from: data) {
                field.imagePath = "\(collectionName).png"
                playField = field
                
                try? savePlayFieldForCollection()
                
                let oldDirectory = playFieldsFolder.appendingPathComponent(collectionName)
                let contents = try? fileManager.contentsOfDirectory(atPath: oldDirectory.path)
                if contents?.isEmpty ?? false {
                    try? fileManager.removeItem(at: oldDirectory)
                }
            }
        }
    }
    
    func setFieldImage(from url: URL) -> Bool {
        do {
            let fileManager = FileManager.default
            let playFieldsFolder = URL.appDocumentsDirectory
                .appendingPathComponent("YouChip-Stat/PlayFields", isDirectory: true)
                .fixedFile()
            
            if !fileManager.fileExists(atPath: playFieldsFolder.path) {
                try fileManager.createDirectory(at: playFieldsFolder, withIntermediateDirectories: true)
            }
            
            let imageName = url.lastPathComponent
            let destinationURL = playFieldsFolder.appendingPathComponent(imageName)
            
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            
            try fileManager.copyItem(at: url, to: destinationURL)
            
            let imageBookmark = destinationURL.makeBookmark()
            
            if let existingField = playField {
                playField = PlayField(
                    id: existingField.id,
                    name: existingField.name,
                    imagePath: imageName,
                    width: existingField.width,
                    height: existingField.height,
                    imageBookmark: imageBookmark
                )
            } else {
                playField = PlayField(
                    id: UUID().uuidString,
                    name: "Field",
                    imagePath: imageName,
                    width: 100.0,
                    height: 60.0,
                    imageBookmark: imageBookmark
                )
            }
            
            return true
        } catch {
            return false
        }
    }
    
    func deleteFieldImage() {
        guard let field = playField else { return }
        
        let fileManager = FileManager.default
        let playFieldsFolder = URL.appDocumentsDirectory
            .appendingPathComponent("YouChip-Stat/PlayFields", isDirectory: true)
            .fixedFile()
        
        let imagePath = playFieldsFolder.appendingPathComponent(field.imagePath)
        
        if fileManager.fileExists(atPath: imagePath.path) {
            try? fileManager.removeItem(at: imagePath)
        }
        
        for i in 0..<tags.count {
            if tags[i].mapEnabled == true {
                tags[i] = Tag(
                    id: tags[i].id,
                    primaryID: tags[i].primaryID,
                    name: tags[i].name,
                    description: tags[i].description,
                    color: tags[i].color,
                    defaultTimeBefore: tags[i].defaultTimeBefore,
                    defaultTimeAfter: tags[i].defaultTimeAfter,
                    collection: tags[i].collection,
                    lablesGroup: tags[i].lablesGroup,
                    hotkey: tags[i].hotkey,
                    labelHotkeys: tags[i].labelHotkeys,
                    mapEnabled: false
                )
            }
        }
        
        playField = nil
        objectWillChange.send()
    }
    
    func updateFieldDimensions(width: Double, height: Double) {
        guard var updatedField = playField else { return }
        updatedField.width = width
        updatedField.height = height
        playField = updatedField
    }
    
    private func stopAccessingResources(urls: [URL]) {
        for url in urls {
            url.stopAccessingSecurityScopedResource()
        }
    }
    
    private func refreshBookmark(collection: String, urls: [URL]) {
        do {
            let tagGroupsBookmark = try urls[0].bookmarkData()
            let tagsBookmark = try urls[1].bookmarkData()
            let labelGroupsBookmark = try urls[2].bookmarkData()
            let labelsBookmark = try urls[3].bookmarkData()
            
            let timeEventsBookmark: Data
            if urls.count > 4 {
                timeEventsBookmark = try urls[4].bookmarkData()
            } else {
                timeEventsBookmark = Data()
            }
            
            let playFieldBookmark: Data
            if urls.count > 5 {
                playFieldBookmark = try urls[5].bookmarkData()
            } else {
                playFieldBookmark = Data()
            }
            
            let refreshedBookmark = CollectionBookmark(
                id: collectionID,
                name: collection,
                tagGroupsBookmark: tagGroupsBookmark,
                tagsBookmark: tagsBookmark,
                labelGroupsBookmark: labelGroupsBookmark,
                labelsBookmark: labelsBookmark,
                timeEventsBookmark: timeEventsBookmark,
                playFieldBookmark: playFieldBookmark
            )
            
            UserDefaults.standard.saveCollectionBookmark(refreshedBookmark)
        } catch {
            print(error)
        }
    }
    
    func createTimeEvent(name: String) -> TimeEvent {
        let newEvent = TimeEvent(
            id: UUID().uuidString,
            name: name
        )
        
        timeEvents.append(newEvent)
        return newEvent
    }
    
    func removeTimeEvent(id: String) {
        timeEvents.removeAll { $0.id == id }
    }
    
    func isHotkeyAssigned(_ hotkey: String?) -> Bool {
        guard let hotkey = hotkey, !hotkey.isEmpty else { return false }
        return tags.contains { $0.hotkey == hotkey }
    }
    
    func isHotkeyAssigned(_ hotkey: String?, excludingTagID: String) -> Bool {
        guard let hotkey = hotkey, !hotkey.isEmpty else { return false }
        return tags.contains { $0.hotkey == hotkey && $0.id != excludingTagID }
    }
    
    func updateTag(id: String, primaryID: String?, name: String, description: String, color: String,
                   defaultTimeBefore: Double, defaultTimeAfter: Double,
                   labelGroupIDs: [String], hotkey: String?, labelHotkeys: [String: String], isInterval: Bool, mapEnabled: Bool) -> Bool {
        if let hotkey = hotkey, !hotkey.isEmpty,
           isHotkeyAssigned(hotkey, excludingTagID: id) {
            return false
        }
        
        if let index = tags.firstIndex(where: { $0.id == id }) {
            let originalTag = tags[index]
            
            if !changedTagIds.contains(id) {
                changedTagIds.append(id)
            }
            
            tags[index] = Tag(
                id: id,
                primaryID: primaryID,
                name: name,
                description: description,
                color: color,
                defaultTimeBefore: defaultTimeBefore,
                defaultTimeAfter: defaultTimeAfter,
                collection: originalTag.collection,
                lablesGroup: labelGroupIDs,
                hotkey: hotkey,
                labelHotkeys: labelHotkeys,
                mapEnabled: mapEnabled,
                isInterval: isInterval
            )
            
            for i in 0..<tagGroups.count {
                if let tagIndex = tagGroups[i].tags.firstIndex(where: { $0 == id }) {
                    var updatedTags = tagGroups[i].tags
                    updatedTags[tagIndex] = id // maybe not needed (remove)
                    tagGroups[i] = TagGroup(
                        id: tagGroups[i].id,
                        name: tagGroups[i].name,
                        tags: updatedTags
                    )
                }
            }
            
            objectWillChange.send()
            return true
        }
        return false
    }
    
    func createTestCollection() {
        collectionName = ^String.Titles.testCollection
        
        let tagGroup = TagGroup(
            id: UUID().uuidString,
            name: ^String.Titles.testTags,
            tags: []
        )
        tagGroups.append(tagGroup)
        
        let tag = Tag(
            id: UUID().uuidString,
            primaryID: nil,
            name: ^String.Titles.testTag,
            description: ^String.Titles.testTagDescription,
            color: "FF5733",
            defaultTimeBefore: 2.0,
            defaultTimeAfter: 3.0,
            collection: collectionName,
            lablesGroup: [],
            hotkey: "T",
            labelHotkeys: nil,
            mapEnabled: true,
            isInterval: false
        )
        tags.append(tag)
        
        if let index = tagGroups.firstIndex(where: { $0.id == tagGroup.id }) {
            tagGroups[index].tags.append(tag.id)
        }
        
        let labelGroup = LabelGroupData(
            id: UUID().uuidString,
            name: ^String.Titles.testLabels,
            lables: []
        )
        labelGroups.append(labelGroup)
        
        let label = Label(
            id: UUID().uuidString,
            name: ^String.Titles.testLabel,
            description: ^String.Titles.testLabelDescription
        )
        labels.append(label)
        if let index = labelGroups.firstIndex(where: { $0.id == labelGroup.id }) {
            labelGroups[index].lables.append(label.id)
        }
        
        let timeEvent = TimeEvent(
            id: UUID().uuidString,
            name: ^String.Titles.testEvent
        )
        timeEvents.append(timeEvent)
    }
    
    func exportCollection() -> URL? {
        let exportData = SportcutCollectionExport(collectionManager: self)
        
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            encoder.dateEncodingStrategy = .iso8601
            
            let jsonData = try encoder.encode(exportData)
            
            let savePanel = NSSavePanel()
            savePanel.allowedContentTypes = [.json]
            savePanel.nameFieldStringValue = "\(collectionName).sportcutCollection"
            savePanel.title = ^String.Titles.exportCollectionTitle
            savePanel.message = ^String.Titles.selectCollectionSaveLocation
            
            if savePanel.runModal() == .OK, let url = savePanel.url {
                try jsonData.write(to: url)
                return url
            }
            
        } catch {
            print(error)
        }
        
        return nil
    }
}
