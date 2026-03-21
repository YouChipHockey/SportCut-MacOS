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
        
        var tagIdMapping: [String: String] = [:]
        var labelIdMapping: [String: String] = [:]
        var timeEventIdMapping: [String: String] = [:]
        
        for label in customCollection.labels {
            let newId = UUID().uuidString
            labelIdMapping[label.id] = newId
            
            let newLabel = Label(
                id: newId,
                name: label.name,
                description: label.description
            )
            
            tagLibraryManager.labels.append(newLabel)
        }
        
        for labelGroup in customCollection.labelGroups {
            var newLabelGroup = labelGroup
            newLabelGroup.id = UUID().uuidString
            
            newLabelGroup.lables = labelGroup.lables.compactMap { oldLabelId in
                return labelIdMapping[oldLabelId]
            }
            
            tagLibraryManager.labelGroups.append(newLabelGroup)
        }
        
        for timeEvent in customCollection.timeEvents {
            let newId = UUID().uuidString
            timeEventIdMapping[timeEvent.id] = newId
            
            let newTimeEvent = TimeEvent(
                id: newId,
                name: timeEvent.name
            )
            
            tagLibraryManager.timeEvents.append(newTimeEvent)
        }
        
        for tag in customCollection.tags {
            let newId = UUID().uuidString
            tagIdMapping[tag.id] = newId
            
            var newTag = tag
            newTag.id = newId
            newTag.collection = customCollection.name
            
            newTag.lablesGroup = tag.lablesGroup.compactMap { oldLabelGroupId in
                if let oldLabelGroup = customCollection.labelGroups.first(where: { $0.id == oldLabelGroupId }) {
                    return tagLibraryManager.labelGroups.first(where: { $0.name == oldLabelGroup.name })?.id
                }
                return nil
            }
            
            tagLibraryManager.tags.append(newTag)
        }
        
        for tagGroup in customCollection.tagGroups {
            var newTagGroup = tagGroup
            newTagGroup.id = UUID().uuidString
            newTagGroup.tags = tagGroup.tags.compactMap { oldTagId in
                return tagIdMapping[oldTagId]
            }
            
            tagLibraryManager.tagGroups.append(newTagGroup)
        }
        
        var updatedTimelines = timelines
        for timelineIndex in 0..<updatedTimelines.count {
            for stampIndex in 0..<updatedTimelines[timelineIndex].stamps.count {
                updatedTimelines[timelineIndex].stamps[stampIndex].tagRefs = updatedTimelines[timelineIndex].stamps[stampIndex].tagRefs.map { ref in
                    StampTagRef(id: tagIdMapping[ref.id] ?? ref.id, tagGroupId: ref.tagGroupId)
                }
                
                var newTimeEvents: [String] = []
                for oldTimeEventId in updatedTimelines[timelineIndex].stamps[stampIndex].timeEvents {
                    if let newTimeEventId = timeEventIdMapping[oldTimeEventId] {
                        newTimeEvents.append(newTimeEventId)
                    }
                }
                updatedTimelines[timelineIndex].stamps[stampIndex].timeEvents = newTimeEvents
            }
        }
        
        tagLibraryManager.refreshGlobalPools()
        
        return updatedTimelines
    }
}
