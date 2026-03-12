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
    
    var changedTags: [(id: String, newName: String)] = []
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
            collectionName = originalName.isEmpty ? collectionID : originalName
        } else {
            collectionName = ensureUniqueCollectionName(collectionName, collectionID: collectionID)
        }
        
        let collection = CollectionData(
            id: collectionID,
            tagGroups: tagGroups,
            tags: tags,
            labelGroups: labelGroups,
            labels: labels,
            timeEvents: timeEvents,
            playField: playField
        )
        
        InMemoryStorageManager.shared.saveCollection(collection)
        
        CollectionsBookmarksManager.shared.saveCollection(id: collectionID, name: collectionName)
        
        originalName = collectionName
        if !isEditingExisting {
            isEditingExisting = true
        }
        
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            NotificationCenter.default.post(
                name: .collectionDataChanged,
                object: nil,
                userInfo: [Notification.Key.collectionName: collectionName]
            )
        }
        
        for tag in changedTags {
            NotificationCenter.default.post(
                name: .tagUpdated,
                object: nil,
                userInfo: ["tagId": tag.id, "newName": tag.newName]
            )
        }
        changedTags.removeAll()
        
        return true
    }
    
    func ensureUniqueCollectionName(_ baseName: String, collectionID: String) -> String {
        let existingNames = CollectionsBookmarksManager.shared
            .loadCollections()
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
        let allCollections = CollectionsBookmarksManager.shared.loadCollections()
        
        guard let collectionInfo = allCollections.first(where: { $0.name == collectionName }) else {
            print("❌ CustomCollectionManager: Collection '\(collectionName)' not found")
            return false
        }
        
        guard let collection = InMemoryStorageManager.shared.loadCollection(id: collectionInfo.id) else {
            print("❌ CustomCollectionManager: Failed to load collection '\(collectionName)'")
            return false
        }
        
        if Thread.isMainThread {
            self.collectionID = collection.id
            self.collectionName = collectionName
            self.tagGroups = collection.tagGroups
            self.tags = collection.tags
            self.labelGroups = collection.labelGroups
            self.labels = collection.labels
            self.timeEvents = collection.timeEvents
            self.playField = collection.playField
        } else {
            DispatchQueue.main.sync {
                self.collectionID = collection.id
                self.collectionName = collectionName
                self.tagGroups = collection.tagGroups
                self.tags = collection.tags
                self.labelGroups = collection.labelGroups
                self.labels = collection.labels
                self.timeEvents = collection.timeEvents
                self.playField = collection.playField
            }
        }
        
        print("✅ CustomCollectionManager: Successfully loaded collection '\(collectionName)'")
        return true
    }
    
    private func loadAllCollections() {
        _ = CollectionsBookmarksManager.shared.loadCollections()
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
            
            let imagePathToSave = playField.imagePath.isEmpty ? "\(collectionName).png" : playField.imagePath
            let updatedField = PlayField(
                id: playField.id,
                name: playField.name,
                imagePath: imagePathToSave,
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
                if field.imagePath.isEmpty {
                    field.imagePath = "\(collectionName).png"
                }
                let imageURL = playFieldsFolder.appendingPathComponent(field.imagePath)
                if fileManager.fileExists(atPath: imageURL.path), let bookmark = imageURL.makeBookmark() {
                    playField = PlayField(
                        id: field.id,
                        name: field.name,
                        imagePath: field.imagePath,
                        width: field.width,
                        height: field.height,
                        imageBookmark: bookmark
                    )
                } else {
                    playField = field
                }
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
            
            let imageName = "\(collectionName).png"
            let destinationURL = playFieldsFolder.appendingPathComponent(imageName)
            
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            
            try fileManager.copyItem(at: url, to: destinationURL)
            
            guard let imageBookmark = destinationURL.makeBookmark() else {
                print("❌ Error setting field image: failed to create bookmark")
                return false
            }
            
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
            _ = savePlayFieldForCollection()
            objectWillChange.send()
            _ = saveCollectionToFiles()
            return true
        } catch {
            print("❌ Error setting field image: \(error)")
            return false
        }
    }
    
    func deleteFieldImage() {
        guard let field = playField else { return }
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            let fileManager = FileManager.default
            let playFieldsFolder = URL.appDocumentsDirectory
                .appendingPathComponent("YouChip-Stat/PlayFields", isDirectory: true)
                .fixedFile()
            
            let imagePath = playFieldsFolder.appendingPathComponent(field.imagePath)
            
            if fileManager.fileExists(atPath: imagePath.path) {
                try? fileManager.removeItem(at: imagePath)
            }
            
            DispatchQueue.main.async {
                for i in 0..<self.tags.count {
                    if self.tags[i].mapEnabled == true {
                        self.tags[i] = Tag(
                            id: self.tags[i].id,
                            primaryID: self.tags[i].primaryID,
                            name: self.tags[i].name,
                            description: self.tags[i].description,
                            color: self.tags[i].color,
                            defaultTimeBefore: self.tags[i].defaultTimeBefore,
                            defaultTimeAfter: self.tags[i].defaultTimeAfter,
                            collection: self.tags[i].collection,
                            lablesGroup: self.tags[i].lablesGroup,
                            hotkey: self.tags[i].hotkey,
                            labelHotkeys: self.tags[i].labelHotkeys,
                            mapEnabled: false
                        )
                    }
                }
                
                self.playField = nil
                self.objectWillChange.send()
                _ = self.saveCollectionToFiles()
            }
        }
    }
    
    func updateFieldDimensions(width: Double, height: Double) {
        guard var updatedField = playField else { return }
        updatedField.width = width
        updatedField.height = height
        playField = updatedField
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
            
            if !changedTags.contains(where: { $0.id == id}) {
                changedTags.append((id, name))
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
