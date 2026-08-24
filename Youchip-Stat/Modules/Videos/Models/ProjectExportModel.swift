//
//  ProjectExportModel.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 02.03.2025.
//

import Foundation

struct ProjectExportModel: Codable {
    let version: String
    let exportDate: Date
    let projectName: String
    let videoMetadata: VideoMetadata
    let timelines: [TimelineLine]
    let customName: String?
    let isFavorite: Bool
    let projectId: String
    let customCollection: CustomCollectionExport?
    /// Карты поля, встроенные в разметку (id карты → картинка). Позволяют визуализировать точки
    /// БЕЗ установленной коллекции. Опционально — старые проекты без него парсятся как раньше.
    let embeddedMaps: [EmbeddedFieldMap]?

    init(projectName: String, videoMetadata: VideoMetadata, timelines: [TimelineLine], customName: String?, isFavorite: Bool, projectId: String, customCollection: CustomCollectionExport? = nil, embeddedMaps: [EmbeddedFieldMap]? = nil) {
        self.version = "1.0"
        self.exportDate = Date()
        self.projectName = projectName
        self.videoMetadata = videoMetadata
        self.timelines = timelines
        self.customName = customName
        self.isFavorite = isFavorite
        self.projectId = projectId
        self.customCollection = customCollection
        self.embeddedMaps = embeddedMaps
    }
}

struct ProjectImportModel: Codable {
    let version: String
    let exportDate: Date
    let projectName: String
    let videoMetadata: VideoMetadata
    let timelines: [TimelineLine]
    let customName: String?
    let isFavorite: Bool
    let projectId: String
    let customCollection: CustomCollectionExport?
    /// См. `ProjectExportModel.embeddedMaps`. Опционально — старые файлы без него валидны.
    let embeddedMaps: [EmbeddedFieldMap]?

    // Явный init с дефолтом для `embeddedMaps` — чтобы XML-импортёры (Nacsport/Sportcode/Dartfish),
    // строящие модель вручную без карт, продолжали компилироваться. Codable-синтез сохраняется.
    init(version: String, exportDate: Date, projectName: String, videoMetadata: VideoMetadata,
         timelines: [TimelineLine], customName: String?, isFavorite: Bool, projectId: String,
         customCollection: CustomCollectionExport?, embeddedMaps: [EmbeddedFieldMap]? = nil) {
        self.version = version
        self.exportDate = exportDate
        self.projectName = projectName
        self.videoMetadata = videoMetadata
        self.timelines = timelines
        self.customName = customName
        self.isFavorite = isFavorite
        self.projectId = projectId
        self.customCollection = customCollection
        self.embeddedMaps = embeddedMaps
    }
}

struct CustomCollectionExport: Codable {
    let name: String
    let tags: [Tag]
    let tagGroups: [TagGroup]
    let labelGroups: [LabelGroupData]
    let labels: [Label]
    let timeEvents: [TimeEvent]
    let playField: PlayField?
    
    init(name: String, tags: [Tag], tagGroups: [TagGroup], labelGroups: [LabelGroupData], labels: [Label], timeEvents: [TimeEvent], playField: PlayField?) {
        self.name = name
        self.tags = tags
        self.tagGroups = tagGroups
        self.labelGroups = labelGroups
        self.labels = labels
        self.timeEvents = timeEvents
        self.playField = playField
    }
    
    init(from sportcutExport: SportcutCollectionExport) {
        self.name = sportcutExport.collectionName
        self.tags = sportcutExport.tags
        self.tagGroups = sportcutExport.tagGroups
        self.labelGroups = sportcutExport.labelGroups
        self.labels = sportcutExport.labels
        self.timeEvents = sportcutExport.timeEvents
        self.playField = sportcutExport.playField?.toPlayField()
    }
}
