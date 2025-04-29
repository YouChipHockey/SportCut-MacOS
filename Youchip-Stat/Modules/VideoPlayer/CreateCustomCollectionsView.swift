//
//  CreateCustomCollectionsView.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 16.04.2025.
//

import SwiftUI
import Foundation

struct CollectionBookmark: Codable {
    let name: String
    let tagGroupsBookmark: Data
    let tagsBookmark: Data
    let labelGroupsBookmark: Data
    let labelsBookmark: Data
    let timeEventsBookmark: Data // Added for time events
}

// MARK: - CustomCollectionManager
class CustomCollectionManager: ObservableObject {
    @Published var tagGroups: [TagGroup] = []
    @Published var tags: [Tag] = []
    @Published var labelGroups: [LabelGroupData] = []
    @Published var labels: [Label] = []
    @Published var timeEvents: [TimeEvent] = []
    @Published var collectionName: String = "МояКоллекция"
    @Published var isEditingExisting: Bool = false
    // Add originalName to track the name before editing
    var originalName: String = ""
    
    init() {}
    
    // Initialize with an existing collection bookmark
    init(withBookmark bookmark: CollectionBookmark) {
        self.isEditingExisting = true
        self.originalName = bookmark.name
        self.collectionName = bookmark.name
        loadCollectionFromBookmarks(named: bookmark.name)
    }
    
    func createTagGroup(name: String) -> TagGroup {
        let newGroup = TagGroup(id: UUID().uuidString, name: name, tags: [])
        tagGroups.append(newGroup)
        return newGroup
    }
    
    func createTag(name: String, description: String, color: String,
                   defaultTimeBefore: Double, defaultTimeAfter: Double,
                   inGroup groupID: String, hotkey: String? = nil) -> Tag {
        // Validate that the hotkey is unique if not nil
        if let hotkey = hotkey, !hotkey.isEmpty {
            if tags.contains(where: { $0.hotkey == hotkey }) {
                // If hotkey is already assigned, use nil instead
                return createTagWithValidatedHotkey(name: name, description: description, color: color,
                                                  defaultTimeBefore: defaultTimeBefore, 
                                                  defaultTimeAfter: defaultTimeAfter,
                                                  inGroup: groupID, hotkey: nil)
            }
        }
        
        return createTagWithValidatedHotkey(name: name, description: description, color: color,
                                          defaultTimeBefore: defaultTimeBefore, 
                                          defaultTimeAfter: defaultTimeAfter,
                                          inGroup: groupID, hotkey: hotkey)
    }
    
    private func createTagWithValidatedHotkey(name: String, description: String, color: String,
                                            defaultTimeBefore: Double, defaultTimeAfter: Double,
                                            inGroup groupID: String, hotkey: String?) -> Tag {
        let newTag = Tag(
            id: UUID().uuidString,
            name: name,
            description: description,
            color: color,
            defaultTimeBefore: defaultTimeBefore,
            defaultTimeAfter: defaultTimeAfter,
            collection: collectionName,
            lablesGroup: [],
            hotkey: hotkey,
            labelHotkeys: [:]
        )
        
        tags.append(newTag)
        
        // Add this tag to the specified group
        if let index = tagGroups.firstIndex(where: { $0.id == groupID }) {
            var updatedGroup = tagGroups[index]
            var updatedTags = updatedGroup.tags
            updatedTags.append(newTag.id)
            
            // Update the group with the new tag
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
        
        // Add this label to the specified group
        if let index = labelGroups.firstIndex(where: { $0.id == groupID }) {
            var updatedGroup = labelGroups[index]
            var updatedLabels = updatedGroup.lables
            updatedLabels.append(newLabel.id)
            
            // Update the group with the new label
            labelGroups[index] = LabelGroupData(
                id: updatedGroup.id,
                name: updatedGroup.name,
                lables: updatedLabels
            )
        }
        
        return newLabel
    }
    
    // Updates the association between tags and label groups
    func updateTagLabelGroups(tagID: String, labelGroupIDs: [String]) {
        if let index = tags.firstIndex(where: { $0.id == tagID }) {
            tags[index] = Tag(
                id: tags[index].id,
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
    
    // Add a tag to a group
    func addTagToGroup(tagID: String, groupID: String) {
        if let index = tagGroups.firstIndex(where: { $0.id == groupID }) {
            var updatedGroup = tagGroups[index]
            if !updatedGroup.tags.contains(tagID) {
                var updatedTags = updatedGroup.tags
                updatedTags.append(tagID)
                
                // Update the group with the new tag
                tagGroups[index] = TagGroup(
                    id: updatedGroup.id,
                    name: updatedGroup.name,
                    tags: updatedTags
                )
            }
        }
    }
    
    // Remove a tag from a group
    func removeTagFromGroup(tagID: String, groupID: String) {
        if let index = tagGroups.firstIndex(where: { $0.id == groupID }) {
            var updatedGroup = tagGroups[index]
            var updatedTags = updatedGroup.tags
            updatedTags.removeAll(where: { $0 == tagID })
            
            // Update the group with the modified tags
            tagGroups[index] = TagGroup(
                id: updatedGroup.id,
                name: updatedGroup.name,
                tags: updatedTags
            )
        }
    }
    
    // Save the collection to files
    func saveCollectionToFiles() -> Bool {
        // If editing an existing collection, always use the original name
        if isEditingExisting {
            collectionName = originalName
        } else {
            // Only for new collections, ensure the name is unique
            collectionName = ensureUniqueCollectionName(collectionName)
        }
        
        do {
            // Prepare the data structures for saving
            let tagGroupsData = TagGroupsData(tagGroups: tagGroups)
            let tagsData = TagsData(tags: tags)
            let labelGroupsData = LabelGroupsData(labelGroups: labelGroups)
            let labelsData = LabelsData(labels: labels)
            let timeEventsData = TimeEventsData(events: timeEvents)
            
            // Get the app support directory
            let fileManager = FileManager.default
            
            let collectionsFolder = URL.appDocumentsDirectory
                .appendingPathComponent("YouChip-Stat/Collections/\(collectionName)", isDirectory: true)
                .fixedFile()
            
            // Create directories if they don't exist (no more renaming support)
            if !fileManager.fileExists(atPath: collectionsFolder.path) {
                try fileManager.createDirectory(at: collectionsFolder, withIntermediateDirectories: true)
            }
            
            // Create file URLs
            let tagGroupsURL = collectionsFolder.appendingPathComponent("tagGroups.json")
            let tagsURL = collectionsFolder.appendingPathComponent("tags.json")
            let labelGroupsURL = collectionsFolder.appendingPathComponent("labelGroups.json")
            let labelsURL = collectionsFolder.appendingPathComponent("labels.json")
            let timeEventsURL = collectionsFolder.appendingPathComponent("timeEvents.json")
            
            // Create the JSON encoder
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            
            // Save files and create security-scoped bookmarks
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
            
            // Create and save collection bookmark
            let collectionBookmark = CollectionBookmark(
                name: collectionName,
                tagGroupsBookmark: tagGroupsBookmark,
                tagsBookmark: tagsBookmark,
                labelGroupsBookmark: labelGroupsBookmark,
                labelsBookmark: labelsBookmark,
                timeEventsBookmark: timeEventsBookmark
            )
            
            UserDefaults.standard.saveCollectionBookmark(collectionBookmark)
            
            // Update originalName to match the new name
            originalName = collectionName
            
            return true
        } catch {
            print("Error saving collection: \(error)")
            return false
        }
    }
    
    // Add a new method to ensure unique collection names
    func ensureUniqueCollectionName(_ baseName: String) -> String {
        let existingNames = UserDefaults.standard.getCollectionBookmarks().map { $0.name }
        
        // If this is an edit operation and the name hasn't changed, or the name doesn't exist, return as is
        if (isEditingExisting && baseName == originalName) || !existingNames.contains(baseName) {
            return baseName
        }
        
        // Find a unique name with a numeric suffix
        var counter = 1
        var newName = "\(baseName) (\(counter))"
        
        while existingNames.contains(newName) {
            counter += 1
            newName = "\(baseName) (\(counter))"
        }
        
        return newName
    }

    // Add method to load collection from bookmarks
    func loadCollectionFromBookmarks(named collectionName: String) -> Bool {
        guard let bookmark = UserDefaults.standard.getCollectionBookmarks()
            .first(where: { $0.name == collectionName }) else {
            print("Error: No bookmark found for collection named '\(collectionName)'")
            return false
        }
        
        do {
            var isStale = false
            
            // Step 1: Try to resolve each bookmark with proper error handling
            var urls: [URL] = []
            var accessFlags: [Bool] = []
            
            // Wrap each URL resolution in its own try-catch to handle individual failures
            do {
                let tagGroupsURL = try URL(resolvingBookmarkData: bookmark.tagGroupsBookmark,
                                         options: .withSecurityScope,
                                         relativeTo: nil,
                                         bookmarkDataIsStale: &isStale)
                urls.append(tagGroupsURL)
                let accessFlag = tagGroupsURL.startAccessingSecurityScopedResource()
                accessFlags.append(accessFlag)
            } catch {
                print("Error resolving tagGroups bookmark: \(error)")
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
                print("Error resolving tags bookmark: \(error)")
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
                print("Error resolving labelGroups bookmark: \(error)")
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
                print("Error resolving labels bookmark: \(error)")
                return false
            }
            
            // Add time events URL resolution
            do {
                // Handle older collection bookmarks that don't have timeEvents
                if bookmark.timeEventsBookmark.isEmpty {
                    print("Note: No time events bookmark found in collection - this might be an older collection format")
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
                print("Error resolving timeEvents bookmark: \(error)")
                // Don't return false here since timeEvents might not exist in older collections
            }
            
            // Check if all essential resources could be accessed
            if urls.count < 4 || accessFlags.contains(false) {
                stopAccessingResources(urls: urls)
                print("Error: Failed to access all required resources")
                return false
            }
            
            // Ensure we clean up access when done or if an error occurs
            defer {
                stopAccessingResources(urls: urls)
            }
            
            // Step 2: Now that we have valid URLs, load the data
            let tagGroupsURL = urls[0]
            let tagsURL = urls[1]
            let labelGroupsURL = urls[2]
            let labelsURL = urls[3]
            
            let decoder = JSONDecoder()
            
            // Step 3: Load and decode each file with its own error handling
            do {
                let tagGroupsData = try Data(contentsOf: tagGroupsURL)
                let tagGroupsContainer = try decoder.decode(TagGroupsData.self, from: tagGroupsData)
                self.tagGroups = tagGroupsContainer.tagGroups
            } catch {
                print("Error loading tag groups data: \(error)")
                return false
            }
            
            do {
                let tagsData = try Data(contentsOf: tagsURL)
                let tagsContainer = try decoder.decode(TagsData.self, from: tagsData)
                self.tags = tagsContainer.tags
            } catch {
                print("Error loading tags data: \(error)")
                return false
            }
            
            do {
                let labelGroupsData = try Data(contentsOf: labelGroupsURL)
                let labelGroupsContainer = try decoder.decode(LabelGroupsData.self, from: labelGroupsData)
                self.labelGroups = labelGroupsContainer.labelGroups
            } catch {
                print("Error loading label groups data: \(error)")
                return false
            }
            
            do {
                let labelsData = try Data(contentsOf: labelsURL)
                let labelsContainer = try decoder.decode(LabelsData.self, from: labelsData)
                self.labels = labelsContainer.labels
            } catch {
                print("Error loading labels data: \(error)")
                return false
            }
            
            // Load time events if available (might not be in older collections)
            if urls.count > 4 {
                let timeEventsURL = urls[4]
                do {
                    let timeEventsData = try Data(contentsOf: timeEventsURL)
                    let timeEventsContainer = try decoder.decode(TimeEventsData.self, from: timeEventsData)
                    self.timeEvents = timeEventsContainer.events
                } catch {
                    print("Error loading time events data: \(error)")
                    // Don't fail the whole load just because time events are missing
                    self.timeEvents = []
                }
            } else {
                self.timeEvents = []
            }
            
            // If all data was successfully loaded, update the collection name
            self.collectionName = collectionName
            
            // If bookmarks are stale, try to refresh them
            if isStale {
                refreshBookmark(collection: collectionName, urls: urls)
            }
            
            return true
        } catch {
            print("Unexpected error loading collection: \(error)")
            return false
        }
    }
    
    // Helper function to stop accessing all resources
    private func stopAccessingResources(urls: [URL]) {
        for url in urls {
            url.stopAccessingSecurityScopedResource()
        }
    }
    
    // Helper function to refresh a bookmark if it's stale
    private func refreshBookmark(collection: String, urls: [URL]) {
        do {
            let tagGroupsBookmark = try urls[0].bookmarkData()
            let tagsBookmark = try urls[1].bookmarkData()
            let labelGroupsBookmark = try urls[2].bookmarkData()
            let labelsBookmark = try urls[3].bookmarkData()
            
            // Handle time events bookmark if available
            let timeEventsBookmark: Data
            if urls.count > 4 {
                timeEventsBookmark = try urls[4].bookmarkData()
            } else {
                timeEventsBookmark = Data()
            }
            
            let refreshedBookmark = CollectionBookmark(
                name: collection,
                tagGroupsBookmark: tagGroupsBookmark,
                tagsBookmark: tagsBookmark,
                labelGroupsBookmark: labelGroupsBookmark,
                labelsBookmark: labelsBookmark,
                timeEventsBookmark: timeEventsBookmark
            )
            
            UserDefaults.standard.saveCollectionBookmark(refreshedBookmark)
            print("Refreshed bookmark for collection: \(collection)")
        } catch {
            print("Failed to refresh bookmark for collection: \(collection), error: \(error)")
        }
    }
    
    // Create a new time event and add it to the collection
    func createTimeEvent(name: String) -> TimeEvent {
        let newEvent = TimeEvent(
            id: UUID().uuidString,
            name: name
        )
        
        timeEvents.append(newEvent)
        return newEvent
    }
    
    // Remove a time event from the collection by its ID
    func removeTimeEvent(id: String) {
        timeEvents.removeAll { $0.id == id }
    }
    
    // Method to check if a hotkey is already assigned to another tag
    func isHotkeyAssigned(_ hotkey: String?) -> Bool {
        guard let hotkey = hotkey, !hotkey.isEmpty else { return false }
        return tags.contains { $0.hotkey == hotkey }
    }
    
    // Method to check if a hotkey is already assigned to another tag, excluding the current tag
    func isHotkeyAssigned(_ hotkey: String?, excludingTagID: String) -> Bool {
        guard let hotkey = hotkey, !hotkey.isEmpty else { return false }
        return tags.contains { $0.hotkey == hotkey && $0.id != excludingTagID }
    }
    
    // Updates the tag with new values including hotkey
    func updateTag(id: String, name: String, description: String, color: String,
                  defaultTimeBefore: Double, defaultTimeAfter: Double,
                  labelGroupIDs: [String], hotkey: String?, labelHotkeys: [String: String]) -> Bool {
        
        // Validate hotkey uniqueness if not nil and not empty
        if let hotkey = hotkey, !hotkey.isEmpty,
           isHotkeyAssigned(hotkey, excludingTagID: id) {
            return false
        }
        
        if let index = tags.firstIndex(where: { $0.id == id }) {
            tags[index] = Tag(
                id: id,
                name: name,
                description: description,
                color: color,
                defaultTimeBefore: defaultTimeBefore,
                defaultTimeAfter: defaultTimeAfter,
                collection: tags[index].collection,
                lablesGroup: labelGroupIDs,
                hotkey: hotkey,
                labelHotkeys: labelHotkeys
            )
            return true
        }
        return false
    }
}

// MARK: - View Models for Editing

struct TagFormData {
    var name: String = ""
    var description: String = ""
    var color: Color = .blue
    var hexColor: String = "0000FF"
    var defaultTimeBefore: Double = 5.0
    var defaultTimeAfter: Double = 3.0
    var selectedLabelGroups: [String] = []
    var hotkey: String? = nil
    var labelHotkeys: [String: String] = [:] // Maps label ID to hotkey
    
    init() {}
    
    init(from tag: Tag) {
        self.name = tag.name
        self.description = tag.description
        self.hexColor = tag.color
        self.color = Color(hex: tag.color)
        self.defaultTimeBefore = tag.defaultTimeBefore
        self.defaultTimeAfter = tag.defaultTimeAfter
        self.selectedLabelGroups = tag.lablesGroup
        self.hotkey = tag.hotkey
        self.labelHotkeys = tag.labelHotkeys ?? [:]
    }
    
    func hexStringFromColor(_ color: Color) -> String {
        let components = color.cgColor?.components
        let r: CGFloat = components?[0] ?? 0.0
        let g: CGFloat = components?[1] ?? 0.0
        let b: CGFloat = components?[2] ?? 0.0
        
        let hexString = String.init(
            format: "%02lX%02lX%02lX",
            lround(Double(r * 255)),
            lround(Double(g * 255)),
            lround(Double(b * 255))
        )
        return hexString
    }
    
    // Check if a label hotkey is already used within this tag
    func isLabelHotkeyUsed(_ hotkey: String?, exceptLabel labelID: String) -> Bool {
        guard let hotkey = hotkey, !hotkey.isEmpty else { return false }
        return labelHotkeys.contains { (key, value) in
            value == hotkey && key != labelID
        }
    }
    
    // Add a new method to assign label hotkey only if it's not used
    mutating func assignLabelHotkey(labelID: String, hotkey: String?) -> Bool {
        // If hotkey is nil or empty, always allow clearing it
        if hotkey == nil || hotkey?.isEmpty == true {
            labelHotkeys[labelID] = nil
            return true
        }
        
        // Check if this hotkey is already assigned to another label
        if isLabelHotkeyUsed(hotkey, exceptLabel: labelID) {
            return false
        }
        
        // Assign the hotkey if it's unique
        labelHotkeys[labelID] = hotkey
        return true
    }
}

// MARK: - Key Capture View
struct KeyCaptureView: NSViewRepresentable {
    @Binding var keyString: String?
    var isCapturing: Binding<Bool>
    
    func makeNSView(context: Context) -> NSView {
        let view = KeyCaptureNSView()
        view.keyString = $keyString
        view.isCapturing = isCapturing
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        if let view = nsView as? KeyCaptureNSView {
            view.keyString = $keyString
            view.isCapturing = isCapturing
            
            if isCapturing.wrappedValue {
                // Ensure the view is part of the window
                DispatchQueue.main.async {
                    view.window?.makeFirstResponder(view)
                }
            }
        }
    }
    
    class KeyCaptureNSView: NSView {
        var keyString: Binding<String?>?
        var isCapturing: Binding<Bool>?
        private var lastFlags: NSEvent.ModifierFlags = []
        
        override var acceptsFirstResponder: Bool { true }
        
        // Ensure the view remains invisible and doesn't expand
        override var intrinsicContentSize: NSSize {
            return NSSize(width: 0, height: 0) // Use zero size instead of 1x1
        }
        
        // Override draw to make sure we don't render anything
        override func draw(_ dirtyRect: NSRect) {
            // Do not draw anything
        }
        
        // Override hit testing to ensure we don't interfere with other views
        override func hitTest(_ point: NSPoint) -> NSView? {
            return isCapturing?.wrappedValue == true ? self : nil
        }
        
        override func keyDown(with event: NSEvent) {
            guard isCapturing?.wrappedValue == true else { return }
            
            // Store current modifiers
            lastFlags = event.modifierFlags
            
            // Convert the key event to a descriptive string representation
            let characters = event.charactersIgnoringModifiers ?? ""
            let modifiers = getModifierFlags(event.modifierFlags)
            
            // Build a human-readable representation of the key combination
            var keyRepresentation = modifiers.joined(separator: "+")
            
            // Only add the key if it's not just a modifier key press
            if !characters.isEmpty && !isOnlyModifier(characters) {
                if !keyRepresentation.isEmpty {
                    keyRepresentation += "+"
                }
                keyRepresentation += getKeyName(event)
                
                // Update the binding and end capturing
                if !keyRepresentation.isEmpty {
                    let oldValue = keyString?.wrappedValue
                    keyString?.wrappedValue = keyRepresentation
                    
                    // If the value didn't change after setting (indicating rejection)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        if self.keyString?.wrappedValue != keyRepresentation && self.keyString?.wrappedValue != nil {
                            // The hotkey was rejected (likely because it was already in use)
                            // Restore the previous value
                            self.keyString?.wrappedValue = oldValue
                        }
                        // End capturing
                        self.isCapturing?.wrappedValue = false
                    }
                }
            }
        }
        
        // Captures flag changes (modifier key presses alone)
        override func flagsChanged(with event: NSEvent) {
            guard isCapturing?.wrappedValue == true else { return }
            
            // Store current flags
            let newFlags = event.modifierFlags
            
            // Check if we're adding modifiers (key down) or removing them (key up)
            let isKeyDown = newFlags.contains(lastFlags)
            lastFlags = newFlags
            
            // Get active modifiers
            let modifiers = getModifierFlags(newFlags)
            
            // On key up of a modifier-only hotkey, assign the hotkey
            if !isKeyDown && !modifiers.isEmpty {
                let keyRepresentation = modifiers.joined(separator: "+")
                if !keyRepresentation.isEmpty {
                    keyString?.wrappedValue = keyRepresentation
                    
                    // End capturing with slight delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        self.isCapturing?.wrappedValue = false
                    }
                }
            }
        }
        
        // Get the human-readable names for modifier keys
        private func getModifierFlags(_ flags: NSEvent.ModifierFlags) -> [String] {
            var modifiers: [String] = []
            
            if flags.contains(.command) {
                modifiers.append("⌘")
            }
            if flags.contains(.option) {
                modifiers.append("⌥")
            }
            if flags.contains(.control) {
                modifiers.append("⌃")
            }
            if flags.contains(.shift) {
                modifiers.append("⇧")
            }
            if flags.contains(.function) {
                modifiers.append("Fn")
            }
            
            return modifiers
        }
        
        // Check if the character is a modifier key itself
        private func isOnlyModifier(_ character: String) -> Bool {
            // These represent modifier keys when pressed alone
            let modifierCharacters = ["\u{F700}", "\u{F701}", "\u{F702}", "\u{F703}"]
            return modifierCharacters.contains(character)
        }
        
        // Get a human-readable name for special keys
        private func getKeyName(_ event: NSEvent) -> String {
            // Get the character itself
            let character = event.charactersIgnoringModifiers ?? ""
            
            // Check for special keys first
            if let specialKey = getSpecialKeyName(event.keyCode) {
                return specialKey
            }
            
            // Handle function keys
            if event.keyCode >= 122 && event.keyCode <= 129 {
                return "F\(event.keyCode - 121)"
            }
            
            // For printable characters, use the character itself
            if !character.isEmpty {
                switch character {
                case " ": return "Space"
                default: return character.uppercased()
                }
            }
            
            // If all else fails, return the key code
            return "Key(\(event.keyCode))"
        }
        
        // Special handling for key up events
        private func getSpecialKeyNameForKeyUp(_ keyCode: UInt16) -> String? {
            if keyCode == 63 {
                return "Fn"
            }
            return nil
        }
        
        // Map keycodes to human-readable names for special keys
        private func getSpecialKeyName(_ keyCode: UInt16) -> String? {
            let keyCodeMap: [UInt16: String] = [
                0x24: "Return",
                0x30: "Tab",
                0x31: "Space",
                0x33: "Delete",
                0x35: "Esc",
                0x7D: "↓",
                0x7E: "↑",
                0x7B: "←",
                0x7C: "→",
                0x73: "Home",
                0x77: "End",
                0x74: "Page Up",
                0x79: "Page Down",
                0x72: "Help",
                0x00: "A",
                0x0B: "B",
                0x08: "C",
                0x02: "D",
                0x0E: "E",
                0x03: "F",
                0x05: "G",
                0x04: "H",
                0x22: "I",
                0x26: "J",
                0x28: "K",
                0x25: "L",
                0x2E: "M",
                0x2D: "N",
                0x1F: "O",
                0x23: "P",
                0x0C: "Q",
                0x0F: "R",
                0x01: "S",
                0x11: "T",
                0x20: "U",
                0x09: "V",
                0x0D: "W",
                0x07: "X",
                0x10: "Y",
                0x06: "Z",
                0x12: "1",
                0x13: "2",
                0x14: "3",
                0x15: "4", 
                0x17: "5",
                0x16: "6",
                0x1A: "7",
                0x1C: "8",
                0x19: "9",
                0x1D: "0",
                0x7A: "F1",
                0x78: "F2",
                0x63: "F3",
                0x76: "F4",
                0x60: "F5",
                0x61: "F6",
                0x62: "F7",
                0x64: "F8",
                0x65: "F9",
                0x6D: "F10",
                0x67: "F11",
                0x6F: "F12",
            ]
            
            return keyCodeMap[keyCode]
        }
    }
}

// Helper to prevent beeps when pressing key combinations
extension NSApplication {
    func preventKeyEquivalent() {
        // This is a hack to prevent system beep on key combinations
        // by intercepting the next key equivalent operation
        DispatchQueue.main.async {
            // Do nothing, this just prevents the system from handling the key event
        }
    }
}

// MARK: - Helper Views

// Add a compatibility button style for older macOS
struct CompatibilityButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(Color.accentColor)
            .foregroundColor(.white)
            .cornerRadius(6)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
    }
}

struct ColorPickerView: View {
    @Binding var selectedColor: Color
    @Binding var hexString: String
    @State private var isExpanded: Bool = false
    
    // Основные 10 цветов для свернутого режима
    let basicColors: [ColorOption] = [
        ColorOption(color: .red, hex: "FF0000"),
        ColorOption(color: .orange, hex: "FFA500"),
        ColorOption(color: .yellow, hex: "FFFF00"),
        ColorOption(color: .green, hex: "00FF00"),
        ColorOption(color: .blue, hex: "0000FF"),
        ColorOption(color: .purple, hex: "800080"),
        ColorOption(color: .pink, hex: "FFC0CB"),
        ColorOption(color: .black, hex: "000000"),
        ColorOption(color: .gray, hex: "808080"),
        ColorOption(color: .white, hex: "FFFFFF")
    ]
    
    // Дополнительные 20 цветов для развернутого режима
    let extendedColors: [ColorOption] = [
        ColorOption(color: Color(hex: "FF4500"), hex: "FF4500"), // OrangeRed
        ColorOption(color: Color(hex: "FF8C00"), hex: "FF8C00"), // DarkOrange
        ColorOption(color: Color(hex: "FFD700"), hex: "FFD700"), // Gold
        ColorOption(color: Color(hex: "ADFF2F"), hex: "ADFF2F"), // GreenYellow
        ColorOption(color: Color(hex: "32CD32"), hex: "32CD32"), // LimeGreen
        ColorOption(color: Color(hex: "008000"), hex: "008000"), // Green
        ColorOption(color: Color(hex: "20B2AA"), hex: "20B2AA"), // LightSeaGreen
        ColorOption(color: Color(hex: "87CEEB"), hex: "87CEEB"), // SkyBlue
        ColorOption(color: Color(hex: "4169E1"), hex: "4169E1"), // RoyalBlue
        ColorOption(color: Color(hex: "000080"), hex: "000080"), // Navy
        ColorOption(color: Color(hex: "8A2BE2"), hex: "8A2BE2"), // BlueViolet
        ColorOption(color: Color(hex: "9370DB"), hex: "9370DB"), // MediumPurple
        ColorOption(color: Color(hex: "FF1493"), hex: "FF1493"), // DeepPink
        ColorOption(color: Color(hex: "C71585"), hex: "C71585"), // MediumVioletRed
        ColorOption(color: Color(hex: "8B4513"), hex: "8B4513"), // SaddleBrown
        ColorOption(color: Color(hex: "A0522D"), hex: "A0522D"), // Sienna
        ColorOption(color: Color(hex: "CD853F"), hex: "CD853F"), // Peru
        ColorOption(color: Color(hex: "D2691E"), hex: "D2691E"), // Chocolate
        ColorOption(color: Color(hex: "2F4F4F"), hex: "2F4F4F"), // DarkSlateGray
        ColorOption(color: Color(hex: "708090"), hex: "708090")  // SlateGray
    ]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Цвет:")
                Spacer()
                Button(action: {
                    isExpanded.toggle()
                }) {
                    Text(isExpanded ? "Свернуть" : "Больше цветов")
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                }
                .buttonStyle(.borderless)
            }
            
            // Сетка с основными цветами (всегда отображается)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 30))], spacing: 10) {
                ForEach(basicColors, id: \.hex) { colorOption in
                    colorCircleView(colorOption: colorOption)
                }
            }
            
            // Дополнительные цвета (отображаются при разворачивании)
            if isExpanded {
                Divider()
                    .padding(.vertical, 5)
                
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 30))], spacing: 10) {
                    ForEach(extendedColors, id: \.hex) { colorOption in
                        colorCircleView(colorOption: colorOption)
                    }
                }
            }
            
            HStack {
                Text("HEX:")
                TextField("HEX:", text: $hexString)
                    .frame(width: 80)
                    .disabled(true)
            }
            
            Rectangle()
                .fill(selectedColor)
                .frame(height: 30)
                .overlay(
                    Text(hexString)
                        .foregroundColor(isDark(hexString) ? .white : .black)
                )
        }
    }
    
    @ViewBuilder
    private func colorCircleView(colorOption: ColorOption) -> some View {
        Circle()
            .fill(colorOption.color)
            .frame(width: 30, height: 30)
            .overlay(
                Circle()
                    .stroke(Color.black, lineWidth: colorOption.hex == hexString ? 2 : 0)
            )
            .overlay(
                Group {
                    if colorOption.hex == hexString {
                        Image(systemName: "checkmark")
                            .foregroundColor(isDark(colorOption.hex) ? .white : .black)
                    }
                }
            )
            .shadow(color: .gray.opacity(0.3), radius: 2, x: 1, y: 1)
            .onTapGesture {
                selectedColor = colorOption.color
                hexString = colorOption.hex
            }
    }
    
    // Определить, если цвет темный для выбора контрастного текста
    private func isDark(_ hexString: String) -> Bool {
        guard hexString.count == 6 else { return false }
        
        var rgb: UInt64 = 0
        Scanner(string: hexString).scanHexInt64(&rgb)
        
        let r = Double((rgb & 0xFF0000) >> 16)
        let g = Double((rgb & 0x00FF00) >> 8)
        let b = Double(rgb & 0x0000FF)
        
        // Формула яркости (0-255): 0.299*R + 0.587*G + 0.114*B
        let brightness = (0.299*r + 0.587*g + 0.114*b)
        
        return brightness < 128
    }
}

// Структура для предопределенных цветов
struct ColorOption {
    let color: Color
    let hex: String
}

// MARK: - Main View
struct CreateCustomCollectionsView: View {
    @StateObject private var collectionManager: CustomCollectionManager
    @State private var viewMode: ViewMode = .tagGroups
    @State private var showAddTagGroupSheet = false
    @State private var showAddLabelGroupSheet = false
    @State private var showAddTagSheet = false
    @State private var showAddLabelSheet = false
    @State private var showAddTimeEventSheet = false
    @State private var newGroupName = ""
    @State private var selectedTagGroupID: String?
    @State private var selectedLabelGroupID: String?
    @State private var selectedTagID: String?
    @State private var selectedLabelID: String?
    @State private var selectedTimeEventID: String?
    @State private var tagFormData = TagFormData()
    @State private var newLabelName = ""
    @State private var newLabelDescription = ""
    @State private var newTimeEventName = ""
    @State private var showSaveSuccess = false
    @State private var isCapturingTagHotkey = false
    @State private var isCapturingLabelHotkeys: [String: Bool] = [:]
    
    // Initialize with a blank collection for creation
    init() {
        _collectionManager = StateObject(wrappedValue: CustomCollectionManager())
    }
    
    // Initialize with an existing collection for editing
    init(existingCollection: CollectionBookmark) {
        _collectionManager = StateObject(wrappedValue: CustomCollectionManager(withBookmark: existingCollection))
    }
    
    enum ViewMode {
        case tagGroups
        case labelGroups
        case timeEvents
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Custom toolbar
            customToolbarView
                .padding()
                .background(Color(NSColor.windowBackgroundColor))
                .border(Color.gray.opacity(0.2), width: 0.5)
            
            NavigationView {
                // Sidebar
                sidebarView
                
                // Detail view
                detailView
            }
        }
        .onDisappear {
            // Post notification when view disappears to ensure collections are refreshed
            NotificationCenter.default.post(name: .collectionDataChanged, object: nil)
            
            // Fix bug #3: Ensure TagLibraryManager restores default data
            TagLibraryManager.shared.restoreDefaultData()
        }
        // Add sheet modifiers here
        .sheet(isPresented: $showAddTagGroupSheet) {
            addGroupSheet(title: "Добавить группу тегов") {
                let _ = collectionManager.createTagGroup(name: newGroupName)
                newGroupName = ""
            }
        }
        .sheet(isPresented: $showAddLabelGroupSheet) {
            addGroupSheet(title: "Добавить группу лейблов") {
                let _ = collectionManager.createLabelGroup(name: newGroupName)
                newGroupName = ""
            }
        }
        .sheet(isPresented: $showAddTagSheet) {
            addTagSheet()
        }
        .sheet(isPresented: $showAddLabelSheet) {
            addLabelSheet()
        }
        .sheet(isPresented: $showAddTimeEventSheet) {
            addTimeEventSheet()
        }
    }
    
    // Custom toolbar view
    var customToolbarView: some View {
        HStack {
            if collectionManager.isEditingExisting {
                // Display collection name as non-editable text when editing existing collection
                Text(collectionManager.collectionName)
                    .frame(width: 200, alignment: .leading)
                    .padding(.vertical, 4)
                    .padding(.horizontal, 5)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(5)
            } else {
                // Allow editing name only for new collections
                FocusAwareTextField(text: $collectionManager.collectionName, placeholder: "Имя коллекции")
                    .frame(width: 200)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
            }
            
            Button(action: {
                if collectionManager.saveCollectionToFiles() {
                    showSaveSuccess = true
                    
                    // Post notification that collection data has changed
                    NotificationCenter.default.post(name: .collectionDataChanged, object: nil)
                    
                    // Hide success message after 2 seconds
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        showSaveSuccess = false
                    }
                }
            }) {
                Text(collectionManager.isEditingExisting ? "Обновить коллекцию" : "Сохранить коллекцию")
            }
            .buttonStyle(CompatibilityButtonStyle())
            
            if showSaveSuccess {
                Text("Сохранено!")
                    .foregroundColor(.green)
            }
            
            Spacer()
            
            Picker("", selection: $viewMode) {
                Text("Группы тегов").tag(ViewMode.tagGroups)
                Text("Группы лейблов").tag(ViewMode.labelGroups)
                Text("Общие события").tag(ViewMode.timeEvents)
            }
            .pickerStyle(.segmented)
            .frame(width: 700)
        }
        .padding(.horizontal)
    }
    
    // Sidebar view - refactored to address compiler performance issues
    var sidebarView: some View {
        List {
            if viewMode == .tagGroups {
                tagGroupsListSection
                
                if let groupID = selectedTagGroupID {
                    tagsInGroupSection(groupID: groupID)
                }
            } else if viewMode == .labelGroups {
                labelGroupsListSection
                
                if let groupID = selectedLabelGroupID {
                    labelsInGroupSection(groupID: groupID)
                }
            } else if viewMode == .timeEvents {
                timeEventsListSection
            }
        }
        .listStyle(SidebarListStyle())
        .frame(minWidth: 250)
    }
    
    // Tag groups section - corrected header syntax
    var tagGroupsListSection: some View {
        Section {
            ForEach(collectionManager.tagGroups) { group in
                tagGroupRowView(group: group)
            }
            
            addTagGroupButton
        } header: {
            Text("Группы тегов")
        }
    }
    
    // Time events list section
    var timeEventsListSection: some View {
        Section {
            ForEach(collectionManager.timeEvents) { event in
                timeEventRowView(event: event)
            }
            
            addTimeEventButton
        } header: {
            Text("Общие события")
        }
    }
    
    // Individual time event row view
    func timeEventRowView(event: TimeEvent) -> some View {
        Text(event.name)
            .padding(.vertical, 2)
            .onTapGesture {
                selectedTimeEventID = event.id
                selectedTagID = nil
                selectedLabelID = nil
                newTimeEventName = event.name
            }
            .background(selectedTimeEventID == event.id ? Color.blue.opacity(0.2) : Color.clear)
    }
    
    // Add time event button
    var addTimeEventButton: some View {
        Button(action: {
            newTimeEventName = ""
            showAddTimeEventSheet = true
        }) {
            HStack {
                Image(systemName: "plus.circle")
                Text("Добавить событие")
            }
        }
    }
    
    // Extract tag group row view to simplify expressions
    func tagGroupRowView(group: TagGroup) -> some View {
        Text(group.name)
            .font(.headline)
            .padding(.vertical, 2)
            .onTapGesture {
                selectedTagGroupID = group.id
                selectedLabelGroupID = nil
                selectedTagID = nil
                selectedLabelID = nil
            }
            .background(selectedTagGroupID == group.id ? Color.blue.opacity(0.2) : Color.clear)
    }
    
    // Extract button to simplify expressions
    var addTagGroupButton: some View {
        Button(action: {
            newGroupName = ""
            showAddTagGroupSheet = true
        }) {
            HStack {
                Image(systemName: "plus.circle")
                Text("Добавить группу")
            }
        }
    }
    
    // Tags in selected group section - corrected header syntax
    func tagsInGroupSection(groupID: String) -> some View {
        Group {
            if let group = collectionManager.tagGroups.first(where: { $0.id == groupID }) {
                Section {
                    let groupTags = getTagsForGroup(groupID: groupID)
                    
                    ForEach(groupTags) { tag in
                        tagRowView(tag: tag)
                    }
                    
                    addTagButton
                } header: {
                    Text("Теги в группе \"\(group.name)\"")
                }
            }
        }
    }
    
    var addTagButton: some View {
        Button(action: {
            showAddTagSheet = true
        }) {
            HStack {
                Image(systemName: "plus.circle")
                Text("Добавить тег")
            }
        }
    }
    
    // Get tags that belong to a specific group
    func getTagsForGroup(groupID: String) -> [Tag] {
        if let group = collectionManager.tagGroups.first(where: { $0.id == groupID }) {
            return collectionManager.tags.filter { tag in
                group.tags.contains(tag.id)
            }
        }
        return []
    }
    
    // Individual tag row view
    func tagRowView(tag: Tag) -> some View {
        HStack {
            Rectangle()
                .fill(Color(hex: tag.color))
                .frame(width: 16, height: 16)
            
            Text(tag.name)
                .padding(.vertical, 2)
            
            if let hotkey = tag.hotkey, !hotkey.isEmpty {
                Spacer()
                Text("⌨️ \(hotkey)")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(4)
            }
        }
        .onTapGesture {
            selectedTagID = tag.id
            selectedLabelID = nil
            tagFormData = TagFormData(from: tag)
        }
        .background(selectedTagID == tag.id ? Color.blue.opacity(0.2) : Color.clear)
    }
    
    // Label groups section - corrected header syntax
    var labelGroupsListSection: some View {
        Section {
            ForEach(collectionManager.labelGroups) { group in
                labelGroupRowView(group: group)
            }
            
            addLabelGroupButton
        } header: {
            Text("Группы лейблов")
        }
    }
    
    // Extract label group row view to simplify expressions
    func labelGroupRowView(group: LabelGroupData) -> some View {
        Text(group.name)
            .font(.headline)
            .padding(.vertical, 2)
            .onTapGesture {
                selectedLabelGroupID = group.id
                selectedTagGroupID = nil
                selectedTagID = nil
                selectedLabelID = nil
            }
            .background(selectedLabelGroupID == group.id ? Color.blue.opacity(0.2) : Color.clear)
    }
    
    // Extract button to simplify expressions
    var addLabelGroupButton: some View {
        Button(action: {
            newGroupName = ""
            showAddLabelGroupSheet = true
        }) {
            HStack {
                Image(systemName: "plus.circle")
                Text("Добавить группу")
            }
        }
    }
    
    // Labels in selected group section - corrected header syntax
    func labelsInGroupSection(groupID: String) -> some View {
        Group {
            if let group = collectionManager.labelGroups.first(where: { $0.id == groupID }) {
                Section {
                    let groupLabels = getLabelsForGroup(groupID: groupID)
                    
                    ForEach(groupLabels) { label in
                        labelRowView(label: label)
                    }
                    
                    addLabelButton
                } header: {
                    Text("Лейблы в группе \"\(group.name)\"")
                }
            }
        }
    }
    
    var addLabelButton: some View {
        Button(action: {
            newLabelName = ""
            newLabelDescription = ""
            showAddLabelSheet = true
        }) {
            HStack {
                Image(systemName: "plus.circle")
                Text("Добавить лейбл")
            }
        }
    }
    
    // Get labels that belong to a specific group
    func getLabelsForGroup(groupID: String) -> [Label] {
        if let group = collectionManager.labelGroups.first(where: { $0.id == groupID }) {
            return collectionManager.labels.filter { label in
                group.lables.contains(label.id)
            }
        }
        return []
    }
    
    // Individual label row view
    func labelRowView(label: Label) -> some View {
        Text(label.name)
            .padding(.vertical, 2)
            .onTapGesture {
                selectedLabelID = label.id
                selectedTagID = nil
                newLabelName = label.name
                newLabelDescription = label.description
            }
            .background(selectedLabelID == label.id ? Color.blue.opacity(0.2) : Color.clear)
    }
    
    // Detail view based on selection
    var detailView: some View {
        VStack {
            if let tagID = selectedTagID,
               let tag = collectionManager.tags.first(where: { $0.id == tagID })
            {
                tagDetailView(tag: tag)
            }
            else if let labelID = selectedLabelID,
                    let label = collectionManager.labels.first(where: { $0.id == labelID })
            {
                labelDetailView(label: label)
            }
            else if let timeEventID = selectedTimeEventID,
                    let event = collectionManager.timeEvents.first(where: { $0.id == timeEventID })
            {
                timeEventDetailView(event: event)
            }
            else if selectedTagGroupID != nil || selectedLabelGroupID != nil {
                if viewMode == .tagGroups {
                    Text("Выберите тег или создайте новый")
                        .font(.headline)
                } else if viewMode == .labelGroups {
                    Text("Выберите лейбл или создайте новый")
                        .font(.headline)
                }
            }
            else {
                if viewMode == .tagGroups {
                    Text("Выберите группу тегов или создайте новую")
                        .font(.headline)
                } else if viewMode == .labelGroups {
                    Text("Выберите группу лейблов или создайте новую")
                        .font(.headline)
                } else if viewMode == .timeEvents {
                    if collectionManager.timeEvents.isEmpty {
                        Text("Добавьте временное событие")
                            .font(.headline)
                    } else {
                        Text("Выберите временное событие для редактирования")
                            .font(.headline)
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    func tagDetailView(tag: Tag) -> some View {
        Form {
            Section(header: Text("Информация о теге")) {
                FocusAwareTextField(text: $tagFormData.name, placeholder: "Название")
                
                TextEditor(text: $tagFormData.description)
                    .frame(height: 100)
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                    )
                    .padding(.vertical, 4)
                
                ColorPickerView(selectedColor: $tagFormData.color, hexString: $tagFormData.hexColor)
                
                HStack {
                    Text("Время до:")
                    Slider(value: $tagFormData.defaultTimeBefore, in: 0...30, step: 1) {
                        Text("\(Int(tagFormData.defaultTimeBefore)) сек")
                    }
                    Text("\(Int(tagFormData.defaultTimeBefore)) сек")
                        .frame(width: 60, alignment: .trailing)
                }
                
                HStack {
                    Text("Время после:")
                    Slider(value: $tagFormData.defaultTimeAfter, in: 0...30, step: 1) {
                        Text("\(Int(tagFormData.defaultTimeAfter)) сек")
                    }
                    Text("\(Int(tagFormData.defaultTimeAfter)) сек")
                        .frame(width: 60, alignment: .trailing)
                }
                
                HStack {
                    Text("Горячая клавиша:")
                    
                    ZStack {
                        // Button to start capturing
                        Button(action: {
                            isCapturingTagHotkey = true
                        }) {
                            HStack {
                                Text(tagFormData.hotkey ?? "Нажмите для назначения")
                                    .foregroundColor(isCapturingTagHotkey ? .blue : .primary)
                                Spacer()
                                
                                if tagFormData.hotkey != nil {
                                    Button(action: {
                                        tagFormData.hotkey = nil
                                    }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundColor(.gray)
                                    }
                                    .buttonStyle(BorderlessButtonStyle())
                                }
                            }
                            .frame(width: 200)
                            .padding(6)
                            .background(Color.gray.opacity(0.2))
                            .cornerRadius(5)
                        }
                        .buttonStyle(BorderlessButtonStyle())
                        .disabled(isCapturingTagHotkey)
                        
                        // Invisible view to capture keystrokes
                        if isCapturingTagHotkey {
                            KeyCaptureView(keyString: $tagFormData.hotkey, isCapturing: $isCapturingTagHotkey)
                                .allowsHitTesting(false)
                        }
                    }
                    
                    if let hotkey = tagFormData.hotkey, 
                       collectionManager.isHotkeyAssigned(hotkey, excludingTagID: tag.id) {
                        Text("Этот хоткей уже используется")
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                }
            }
            
            Section(header: Text("Связанные группы лейблов")) {
                VStack(spacing: 12) {
                    ForEach(collectionManager.labelGroups) { group in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(group.name)
                                    .font(.headline)
                                Spacer()
                                Toggle("", isOn: Binding(
                                    get: { tagFormData.selectedLabelGroups.contains(group.id) },
                                    set: { isSelected in
                                        if isSelected {
                                            tagFormData.selectedLabelGroups.append(group.id)
                                        } else {
                                            tagFormData.selectedLabelGroups.removeAll { $0 == group.id }
                                        }
                                    }
                                ))
                                .labelsHidden()
                            }
                            
                            // Only show labels if this group is selected
                            if tagFormData.selectedLabelGroups.contains(group.id) {
                                // Get all labels in this group
                                ForEach(getLabelsForGroup(groupID: group.id)) { label in
                                    HStack {
                                        Text("• \(label.name)")
                                            .padding(.leading, 10)
                                        
                                        Spacer()
                                        
                                        // Hotkey assignment for this label
                                        ZStack {
                                            // Button to start capturing label hotkey
                                            Button(action: {
                                                // Set all other capturing to false
                                                isCapturingTagHotkey = false
                                                for (key, _) in isCapturingLabelHotkeys {
                                                    isCapturingLabelHotkeys[key] = false
                                                }
                                                // Start capturing for this label
                                                isCapturingLabelHotkeys[label.id] = true
                                            }) {
                                                HStack {
                                                    Text(tagFormData.labelHotkeys[label.id] ?? "Назначить")
                                                        .foregroundColor(isCapturingLabelHotkeys[label.id] == true ? .blue : .primary)
                                                        .lineLimit(1)
                                                    
                                                    if tagFormData.labelHotkeys[label.id] != nil {
                                                        Button(action: {
                                                            tagFormData.labelHotkeys.removeValue(forKey: label.id)
                                                        }) {
                                                            Image(systemName: "xmark.circle.fill")
                                                                .foregroundColor(.gray)
                                                        }
                                                        .buttonStyle(BorderlessButtonStyle())
                                                        .padding(.leading, 4)
                                                    }
                                                }
                                                .frame(width: 120)
                                                .padding(4)
                                                .background(Color.gray.opacity(0.2))
                                                .cornerRadius(4)
                                            }
                                            .buttonStyle(BorderlessButtonStyle())
                                            .disabled(isCapturingLabelHotkeys[label.id] == true)
                                            
                                            // Invisible view to capture keystrokes
                                            if isCapturingLabelHotkeys[label.id] == true {
                                                KeyCaptureView(
                                                    keyString: Binding(
                                                        get: { tagFormData.labelHotkeys[label.id] },
                                                        set: { tagFormData.labelHotkeys[label.id] = $0 }
                                                    ),
                                                    isCapturing: Binding(
                                                        get: { isCapturingLabelHotkeys[label.id] == true },
                                                        set: { isCapturingLabelHotkeys[label.id] = $0 }
                                                    )
                                                )
                                                .allowsHitTesting(false)
                                            }
                                        }
                                        
                                        // Show warning if hotkey is already used by another label in this tag
                                        if let hotkey = tagFormData.labelHotkeys[label.id], 
                                           tagFormData.isLabelHotkeyUsed(hotkey, exceptLabel: label.id) {
                                            Image(systemName: "exclamationmark.triangle.fill")
                                                .foregroundColor(.orange)
                                                .help("Этот хоткей уже используется другим лейблом")
                                        }
                                    }
                                    .padding(.vertical, 2)
                                }
                            }
                        }
                        .padding(8)
                        .background(Color.gray.opacity(0.05))
                        .cornerRadius(8)
                    }
                }
                .padding(.vertical, 4)
            }
            
            Button("Сохранить изменения") {
                let success = collectionManager.updateTag(
                    id: tag.id,
                    name: tagFormData.name,
                    description: tagFormData.description,
                    color: tagFormData.hexColor,
                    defaultTimeBefore: tagFormData.defaultTimeBefore,
                    defaultTimeAfter: tagFormData.defaultTimeAfter,
                    labelGroupIDs: tagFormData.selectedLabelGroups,
                    hotkey: tagFormData.hotkey,
                    labelHotkeys: tagFormData.labelHotkeys
                )
                
                if !success {
                    // Handle error case
                }
            }
            .buttonStyle(CompatibilityButtonStyle())
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top)
        }
        .padding()
        .onAppear {
            // Initialize capturing state for all labels in selected groups
            isCapturingLabelHotkeys = [:]
            for groupID in tagFormData.selectedLabelGroups {
                for label in getLabelsForGroup(groupID: groupID) {
                    isCapturingLabelHotkeys[label.id] = false
                }
            }
        }
    }
    
    func labelDetailView(label: Label) -> some View {
        Form {
            Section(header: Text("Информация о лейбле")) {
                FocusAwareTextField(text: $newLabelName, placeholder: "Название")
                
                TextEditor(text: $newLabelDescription)
                    .frame(height: 100)
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                    )
                    .padding(.vertical, 4)
            }
            
            Section(header: Text("Связанные теги")) {
                List {
                    ForEach(collectionManager.tags.filter { tag in
                        tag.lablesGroup.contains { groupID in
                            if let group = collectionManager.labelGroups.first(where: { $0.id == groupID }) {
                                return group.lables.contains(label.id)
                            }
                            return false
                        }
                    }) { tag in
                        HStack {
                            Rectangle()
                                .fill(Color(hex: tag.color))
                                .frame(width: 16, height: 16)
                            
                            Text(tag.name)
                        }
                    }
                }
                .frame(height: 150)
                
                Text("Для изменения связей, выберите тег и добавьте группу лейблов к нему.")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            
            Button("Сохранить изменения") {
                if let index = collectionManager.labels.firstIndex(where: { $0.id == label.id }) {
                    collectionManager.labels[index] = Label(
                        id: label.id,
                        name: newLabelName,
                        description: newLabelDescription
                    )
                }
            }
            .buttonStyle(CompatibilityButtonStyle())
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top)
        }
        .padding()
    }
    
    func timeEventDetailView(event: TimeEvent) -> some View {
        Form {
            Section(header: Text("Информация о событии")) {
                FocusAwareTextField(text: $newTimeEventName, placeholder: "Название")
            }
            
            Button("Сохранить изменения") {
                if let index = collectionManager.timeEvents.firstIndex(where: { $0.id == event.id }) {
                    collectionManager.timeEvents[index] = TimeEvent(
                        id: event.id,
                        name: newTimeEventName
                    )
                }
            }
            .buttonStyle(CompatibilityButtonStyle())
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top)
            
            Button("Удалить событие") {
                collectionManager.removeTimeEvent(id: event.id)
                selectedTimeEventID = nil
            }
            .foregroundColor(.red)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top)
        }
        .padding()
    }
    
    // Sheet for adding a new group
    func addGroupSheet(title: String, onAdd: @escaping () -> Void) -> some View {
        VStack(spacing: 16) {
            Text(title)
                .font(.headline)
                .padding(.top)
            
            FocusAwareTextField(text: $newGroupName, placeholder: "Название группы")
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding(.horizontal)
            
            HStack {
                Button("Отмена") {
                    if title.contains("тегов") {
                        showAddTagGroupSheet = false
                    } else {
                        showAddLabelGroupSheet = false
                    }
                }
                .keyboardShortcut(.escape)
                
                Button("Добавить") {
                    onAdd()
                    if title.contains("тегов") {
                        showAddTagGroupSheet = false
                    } else {
                        showAddLabelGroupSheet = false
                    }
                }
                .keyboardShortcut(.return)
                .disabled(newGroupName.isEmpty)
                .buttonStyle(CompatibilityButtonStyle())
            }
            .padding()
        }
        .frame(width: 400)
        .fixedSize(horizontal: false, vertical: true)
    }
    
    // Sheet for adding a new tag
    func addTagSheet() -> some View {
        VStack(spacing: 16) {
            Text("Добавить новый тег")
                .font(.headline)
                .padding(.top)
            
            Form {
                FocusAwareTextField(text: $tagFormData.name, placeholder: "Название")
                
                TextEditor(text: $tagFormData.description)
                    .frame(height: 100)
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                    )
                    .padding(.vertical, 4)
                
                ColorPickerView(selectedColor: $tagFormData.color, hexString: $tagFormData.hexColor)
                
                HStack {
                    Text("Время до:")
                    Slider(value: $tagFormData.defaultTimeBefore, in: 0...30, step: 1)
                    Text("\(Int(tagFormData.defaultTimeBefore)) сек")
                        .frame(width: 60, alignment: .trailing)
                }
                
                HStack {
                    Text("Время после:")
                    Slider(value: $tagFormData.defaultTimeAfter, in: 0...30, step: 1)
                    Text("\(Int(tagFormData.defaultTimeAfter)) сек")
                        .frame(width: 60, alignment: .trailing)
                }
                
                HStack {
                    Text("Горячая клавиша:")
                    
                    ZStack {
                        // Button to start capturing
                        Button(action: {
                            isCapturingTagHotkey = true
                        }) {
                            HStack {
                                Text(tagFormData.hotkey ?? "Нажмите для назначения")
                                    .foregroundColor(isCapturingTagHotkey ? .blue : .primary)
                                Spacer()
                                
                                if tagFormData.hotkey != nil {
                                    Button(action: {
                                        tagFormData.hotkey = nil
                                    }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundColor(.gray)
                                    }
                                    .buttonStyle(BorderlessButtonStyle())
                                }
                            }
                            .frame(width: 200)
                            .padding(6)
                            .background(Color.gray.opacity(0.2))
                            .cornerRadius(5)
                        }
                        .buttonStyle(BorderlessButtonStyle())
                        .disabled(isCapturingTagHotkey)
                        
                        // Invisible view to capture keystrokes
                        if isCapturingTagHotkey {
                            KeyCaptureView(keyString: $tagFormData.hotkey, isCapturing: $isCapturingTagHotkey)
                                .allowsHitTesting(false)
                        }
                    }
                    
                    if let hotkey = tagFormData.hotkey, 
                       collectionManager.isHotkeyAssigned(hotkey) {
                        Text("Этот хоткей уже используется")
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                }
            }
            .padding()
            
            HStack {
                Button("Отмена") {
                    showAddTagSheet = false
                    tagFormData = TagFormData()
                }
                .keyboardShortcut(.escape)
                
                Button("Добавить") {
                    if let groupID = selectedTagGroupID {
                        let newTag = collectionManager.createTag(
                            name: tagFormData.name,
                            description: tagFormData.description,
                            color: tagFormData.hexColor,
                            defaultTimeBefore: tagFormData.defaultTimeBefore,
                            defaultTimeAfter: tagFormData.defaultTimeAfter,
                            inGroup: groupID,
                            hotkey: tagFormData.hotkey
                        )
                        
                        // Update label groups association and hotkeys
                        if !tagFormData.selectedLabelGroups.isEmpty {
                            collectionManager.updateTag(
                                id: newTag.id,
                                name: newTag.name,
                                description: newTag.description,
                                color: newTag.color,
                                defaultTimeBefore: newTag.defaultTimeBefore,
                                defaultTimeAfter: newTag.defaultTimeAfter,
                                labelGroupIDs: tagFormData.selectedLabelGroups,
                                hotkey: newTag.hotkey,
                                labelHotkeys: tagFormData.labelHotkeys
                            )
                        }
                        
                        // Reset form data
                        tagFormData = TagFormData()
                    }
                    showAddTagSheet = false
                }
                .keyboardShortcut(.return)
                .disabled(tagFormData.name.isEmpty || selectedTagGroupID == nil)
                .buttonStyle(CompatibilityButtonStyle())
            }
            .padding()
        }
        .frame(width: 500)
        .onAppear {
            tagFormData = TagFormData()
            isCapturingTagHotkey = false
            isCapturingLabelHotkeys = [:]
        }
    }
    
    // Sheet for adding a new label
    func addLabelSheet() -> some View {
        VStack(spacing: 16) {
            Text("Добавить новый лейбл")
                .font(.headline)
                .padding(.top)
            
            Form {
                FocusAwareTextField(text: $newLabelName, placeholder: "Название")
                
                TextEditor(text: $newLabelDescription)
                    .frame(height: 100)
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                    )
                    .padding(.vertical, 4)
            }
            .padding()
            
            HStack {
                Button("Отмена") {
                    showAddLabelSheet = false
                    newLabelName = ""
                    newLabelDescription = ""
                }
                .keyboardShortcut(.escape)
                
                Button("Добавить") {
                    if let groupID = selectedLabelGroupID {
                        collectionManager.createLabel(
                            name: newLabelName,
                            description: newLabelDescription,
                            inGroup: groupID
                        )
                        
                        // Reset form data
                        newLabelName = ""
                        newLabelDescription = ""
                    }
                    showAddLabelSheet = false
                }
                .keyboardShortcut(.return)
                .disabled(newLabelName.isEmpty || selectedLabelGroupID == nil)
                .buttonStyle(CompatibilityButtonStyle())
            }
            .padding()
        }
        .frame(width: 500)
    }
    
    // Sheet for adding a new time event
    func addTimeEventSheet() -> some View {
        VStack(spacing: 16) {
            Text("Добавить новое временное событие")
                .font(.headline)
                .padding(.top)
            
            Form {
                FocusAwareTextField(text: $newTimeEventName, placeholder: "Название")
            }
            .padding()
            
            HStack {
                Button("Отмена") {
                    showAddTimeEventSheet = false
                    newTimeEventName = ""
                }
                .keyboardShortcut(.escape)
                
                Button("Добавить") {
                    collectionManager.createTimeEvent(name: newTimeEventName)
                    
                    // Reset form data
                    newTimeEventName = ""
                    showAddTimeEventSheet = false
                }
                .keyboardShortcut(.return)
                .disabled(newTimeEventName.isEmpty)
                .buttonStyle(CompatibilityButtonStyle())
            }
            .padding()
        }
        .frame(width: 500)
    }
}

extension UserDefaults {
    private enum Keys {
        static let collections = "savedCollections"
    }
    
    func saveCollectionBookmark(_ bookmark: CollectionBookmark) {
        var collections = getCollectionBookmarks()
        
        // Update existing or add new
        if let index = collections.firstIndex(where: { $0.name == bookmark.name }) {
            collections[index] = bookmark
        } else {
            collections.append(bookmark)
        }
        
        if let encoded = try? JSONEncoder().encode(collections) {
            set(encoded, forKey: Keys.collections)
        }
    }
    
    func getCollectionBookmarks() -> [CollectionBookmark] {
        guard let data = data(forKey: Keys.collections),
              let collections = try? JSONDecoder().decode([CollectionBookmark].self, from: data) else {
            return []
        }
        return collections
    }
    
    func removeCollectionBookmark(named name: String) {
        var collections = getCollectionBookmarks()
        collections.removeAll { $0.name == name }
        
        if let encoded = try? JSONEncoder().encode(collections) {
            set(encoded, forKey: Keys.collections)
        }
    }
}
