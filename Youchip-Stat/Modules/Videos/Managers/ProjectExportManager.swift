//
//  ProjectExportManager.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 02.03.2025.
//

import Foundation
import AppKit
import UniformTypeIdentifiers

class ProjectExportManager {
    static let shared = ProjectExportManager()
    
    private init() {}
    
    func exportProject(file: FilesFile) {
        let projectData = createProjectData(from: file)
        
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [UTType.json]
        savePanel.nameFieldStringValue = "\(file.name).youchip"
        savePanel.title = ^String.Titles.exportProject
        savePanel.message = ^String.Titles.selectProjectSaveLocation
        
        savePanel.begin { response in
            if response == .OK, let url = savePanel.url {
                self.saveProject(projectData, to: url)
            }
        }
    }
    
    private func createProjectData(from file: FilesFile) -> ProjectExportModel {
        let videoMetadata = VideoMetadata(
            team1: extractTeam1(from: file.name),
            team2: extractTeam2(from: file.name),
            score: extractScore(from: file.name),
            url: file.url,
            dateTime: file.dateAdded
        )
        
        let timelines = file.timelines
        let customCollection = collectCustomTagsFromTimelines(timelines)
        
        return ProjectExportModel(
            projectName: file.name,
            videoMetadata: videoMetadata,
            timelines: timelines,
            customName: file.videoData.customName,
            isFavorite: file.videoData.isFavorite ?? false,
            projectId: file.id,
            customCollection: customCollection
        )
    }
    
    private func extractTeam1(from fileName: String) -> String {
        let components = fileName.components(separatedBy: "_")
        return components.count > 0 ? components[0] : ""
    }
    
    private func extractTeam2(from fileName: String) -> String {
        let components = fileName.components(separatedBy: "_")
        return components.count > 1 ? components[1] : ""
    }
    
    private func extractScore(from fileName: String) -> String {
        let components = fileName.components(separatedBy: "_")
        return components.count > 2 ? components[2] : ""
    }
    
    private func saveProject(_ projectData: ProjectExportModel, to url: URL) {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = .prettyPrinted
            
            let data = try encoder.encode(projectData)
            try data.write(to: url)
            
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = ^String.Titles.projectExportedSuccessfully
                alert.informativeText = String(format: ^String.Titles.projectSavedToFile, url.lastPathComponent)
                alert.alertStyle = .informational
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
        } catch {
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = ^String.Titles.exportError
                alert.informativeText = String(format: ^String.Titles.failedToSaveProject, error.localizedDescription)
                alert.alertStyle = .critical
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
        }
    }
    
    func importProject(completion: @escaping (ProjectImportModel?) -> Void) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = ^String.Titles.projectImportChooseFormatTitle
            alert.informativeText = ^String.Titles.projectImportChooseFormatMessage
            alert.addButton(withTitle: ^String.Titles.projectImportSportcutFormat)
            alert.addButton(withTitle: ^String.Titles.projectImportSportcodeXmlFormat)
            alert.addButton(withTitle: ^String.Titles.cancelButtonTitle)
            
            let response = alert.runModal()
            switch response {
            case .alertFirstButtonReturn:
                self.presentSportcutJSONImportPanel(completion: completion)
            case .alertSecondButtonReturn:
                self.presentSportcodeXMLImportPanel(completion: completion)
            default:
                completion(nil)
            }
        }
    }
    
    private func presentSportcutJSONImportPanel(completion: @escaping (ProjectImportModel?) -> Void) {
        let openPanel = NSOpenPanel()
        openPanel.allowedContentTypes = [UTType.json]
        openPanel.title = ^String.Titles.projectImportTitle
        openPanel.message = ^String.Titles.selectProjectFileForImport
        openPanel.allowsMultipleSelection = false
        
        openPanel.begin { response in
            if response == .OK, let url = openPanel.url {
                self.loadProject(from: url, completion: completion)
            } else {
                completion(nil)
            }
        }
    }
    
    private func presentSportcodeXMLImportPanel(completion: @escaping (ProjectImportModel?) -> Void) {
        let openPanel = NSOpenPanel()
        openPanel.allowedContentTypes = [UTType.xml]
        openPanel.title = ^String.Titles.projectImportTitle
        openPanel.message = ^String.Titles.selectSportcodeXmlForImport
        openPanel.allowsMultipleSelection = false
        
        openPanel.begin { response in
            if response == .OK, let url = openPanel.url {
                self.loadProjectFromSportcodeXML(url: url, completion: completion)
            } else {
                completion(nil)
            }
        }
    }
    
    private func loadProjectFromSportcodeXML(url: URL, completion: @escaping (ProjectImportModel?) -> Void) {
        do {
            let data = try Data(contentsOf: url)
            let model = try SportcodeXMLProjectImporter.makeProjectImport(from: data, fileName: url.lastPathComponent)
            completion(model)
        } catch {
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = ^String.Titles.importError
                alert.informativeText = error.localizedDescription
                alert.alertStyle = .critical
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
            completion(nil)
        }
    }
    
    private func loadProject(from url: URL, completion: @escaping (ProjectImportModel?) -> Void) {
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            
            let projectData = try decoder.decode(ProjectImportModel.self, from: data)
            completion(projectData)
        } catch {
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = ^String.Titles.importError
                alert.informativeText = String(format: ^String.Titles.failedToLoadProject, error.localizedDescription)
                alert.alertStyle = .critical
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
            completion(nil)
        }
    }
    
    func createProjectFromImport(projectData: ProjectImportModel, videoBookmark: Data?) -> FilesFile? {
        let filesManager = VideoFilesManager.shared
        
        let newId = filesManager.generate32CharacterCode()
        
        let bookmark: Data
        if let videoBookmark = videoBookmark {
            bookmark = videoBookmark
        } else {
            bookmark = Data()
        }
        
        var updatedTimelines = projectData.timelines
        if let customCollection = projectData.customCollection {
            updatedTimelines = importCustomCollection(customCollection, timelines: projectData.timelines)
        }
        
        let videoData = VideosData(
            bookmark: bookmark,
            id: newId,
            customName: projectData.customName,
            isFavorite: projectData.isFavorite
        )
        
        var file = FilesFile(videoData: videoData)
        file.updateDateOpened()
        file.updateDateModified()
        
        filesManager.addFileWithData(file, videoData: videoData)
        
        // Save timelines to file
        filesManager.saveTimelines(updatedTimelines, for: newId)
        
        return file
    }
    
    private func collectCustomTagsFromTimelines(_ timelines: [TimelineLine]) -> CustomCollectionExport? {
        let tagLibraryManager = TagLibraryManager.shared
        
        var usedTagIds = Set<String>()
        for timeline in timelines {
            for stamp in timeline.stamps {
                stamp.idTags.forEach { usedTagIds.insert($0) }
            }
        }
        
        var customTags: [Tag] = []
        var customTagGroups: [TagGroup] = []
        var customLabelGroups: [LabelGroupData] = []
        var customLabels: [Label] = []
        var customTimeEvents: [TimeEvent] = []
        
        for tagId in usedTagIds {
            if let tag = tagLibraryManager.findTagById(tagId) {
                if isCustomTag(tag) {
                    customTags.append(tag)
                    
                    if let tagGroup = tagLibraryManager.findTagGroupForTag(tagId) {
                        if !customTagGroups.contains(where: { $0.id == tagGroup.id }) {
                            customTagGroups.append(tagGroup)
                        }
                    }
                    
                    let labels = tagLibraryManager.findLabelsForTag(tag)
                    for label in labels {
                        if !customLabels.contains(where: { $0.id == label.id }) {
                            customLabels.append(label)
                        }
                    }
                }
            }
        }
        
        if customTags.isEmpty {
            return nil
        }
        
        for tag in customTags {
            for labelGroupId in tag.lablesGroup {
                if let labelGroup = tagLibraryManager.allLabelGroups.first(where: { $0.id == labelGroupId }) {
                    if !customLabelGroups.contains(where: { $0.id == labelGroup.id }) {
                        customLabelGroups.append(labelGroup)
                    }
                }
            }
        }
        
        var usedTimeEventIds = Set<String>()
        for timeline in timelines {
            for stamp in timeline.stamps {
                for timeEventId in stamp.timeEvents {
                    usedTimeEventIds.insert(timeEventId)
                }
            }
        }
        
        for timeEventId in usedTimeEventIds {
            if let timeEvent = tagLibraryManager.allTimeEvents.first(where: { $0.id == timeEventId }) {
                if !customTimeEvents.contains(where: { $0.id == timeEvent.id }) {
                    customTimeEvents.append(timeEvent)
                }
            }
        }
        
        return CustomCollectionExport(
            name: "Custom Collection for \(Date().formatted(date: .abbreviated, time: .shortened))",
            tags: customTags,
            tagGroups: customTagGroups,
            labelGroups: customLabelGroups,
            labels: customLabels,
            timeEvents: customTimeEvents,
            playField: nil as PlayField?
        )
    }
    
    private func isCustomTag(_ tag: Tag) -> Bool {
        guard let collection = tag.collection else { return true }
        
        let tagLibraryManager = TagLibraryManager.shared
        return !tagLibraryManager.standardCollections.contains { $0.name == collection }
    }
    
    private func importCustomCollection(_ customCollection: CustomCollectionExport, timelines: [TimelineLine]) -> [TimelineLine] {
        let tagLibraryManager = TagLibraryManager.shared

        // Strategy: preserve ORIGINAL IDs from the exported file.
        // If an entity with the same ID already exists in TagLibrary, skip it.
        // If not, add it with its original ID. This ensures stamps (which reference
        // these IDs) and on-disk collection files stay in sync.

        for label in customCollection.labels {
            if !tagLibraryManager.labels.contains(where: { $0.id == label.id }) {
                tagLibraryManager.labels.append(label)
            }
        }

        for labelGroup in customCollection.labelGroups {
            if !tagLibraryManager.labelGroups.contains(where: { $0.id == labelGroup.id }) {
                tagLibraryManager.labelGroups.append(labelGroup)
            }
        }

        for timeEvent in customCollection.timeEvents {
            if !tagLibraryManager.timeEvents.contains(where: { $0.id == timeEvent.id }) {
                tagLibraryManager.timeEvents.append(timeEvent)
            }
        }

        for tag in customCollection.tags {
            if !tagLibraryManager.tags.contains(where: { $0.id == tag.id }) {
                var importedTag = tag
                importedTag.collection = customCollection.name
                tagLibraryManager.tags.append(importedTag)
            }
        }

        for tagGroup in customCollection.tagGroups {
            if let idx = tagLibraryManager.tagGroups.firstIndex(where: { $0.id == tagGroup.id }) {
                // Merge any missing tags into the existing group
                var existing = tagLibraryManager.tagGroups[idx]
                for tagId in tagGroup.tags where !existing.tags.contains(tagId) {
                    existing.tags.append(tagId)
                }
                tagLibraryManager.tagGroups[idx] = existing
            } else {
                tagLibraryManager.tagGroups.append(tagGroup)
            }
        }

        tagLibraryManager.refreshGlobalPools()

        // No ID remapping needed — timelines already reference the original IDs
        return timelines
    }
}
