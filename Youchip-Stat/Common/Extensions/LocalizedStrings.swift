//
//  LocalizedStrings.swift
//  smm-printer-mac
//
//  Created by Сергей Бекезин on 04.06.2024.
//

import Foundation

extension String {
    
    func capitalizeFirstLetter() -> String {
        return prefix(1).capitalized + dropFirst()
    }
    
    enum Titles: String {
        case cancelButtonTitle
        case deleteButtonTitle
        case fullControlButtonExportLabels
        case saveButtonTitle
        case closeButtonTitle
        case previousButtonTitle
        case alertsOkTitle
        case alertsErrorTitle
        case alertsInfoTitle
        case alertsYesTitle
        case alertsNoTitle
        case alertsAreYouSure
        case alertsLikeAlertTitle
        case alertsOcrErrorTitle
        case alertsOpenFileErrorTitle
        case alertsFileErrorTitle
        case alertsUnknowErrorTitle
        case alertsEmptyFileErrorTitle
        case alertsBadFileErrorTitle
        case addVideoTitle
        case macQuitAppTitle
        case rootYouChipTitle
        case rootVideosTitle
        case rootTheFileIsPlacedInCloudTitle
        case rootDownloadTitle
        case rootDownloadingHasStartedTitle
        
        case fieldMapTitleTagsList // ^String.Titles.fieldMapTitleTagsList
        case fieldMapButtonFilters // ^String.Titles.fieldMapButtonFilters
        case fieldMapHelpResetFilters // ^String.Titles.fieldMapHelpResetFilters
        case fieldMapTagNoFilters // ^String.Titles.fieldMapTagNoFilters
        case fieldMapLabelLabels // ^String.Titles.fieldMapLabelLabels
        case fieldMapLabelEvents // ^String.Titles.fieldMapLabelEvents
        case fieldMapFooterFiltered // ^String.Titles.fieldMapFooterFiltered
        case fieldMapFooterDisplayed // ^String.Titles.fieldMapFooterDisplayed
        case fieldMapViewTags // ^String.Titles.fieldMapViewTags
        case fieldMapViewHeatmap // ^String.Titles.fieldMapViewHeatmap
        case fieldMapButtonExport // ^String.Titles.fieldMapButtonExport
        case fieldMapHelpExportImage // ^String.Titles.fieldMapHelpExportImage
        case fieldMapLoading // ^String.Titles.fieldMapLoading
        case fieldMapNoMap // ^String.Titles.fieldMapNoMap
        case fieldMapWindowExportTitle // ^String.Titles.fieldMapWindowExportTitle
        case fieldMapSavePanelTitle // ^String.Titles.fieldMapSavePanelTitle
        case fieldMapSavePanelMessage // ^String.Titles.fieldMapSavePanelMessage
        case fieldMapSavePanelDefaultName // ^String.Titles.fieldMapSavePanelDefaultName
        case fieldMapAlertErrorTitle // ^String.Titles.fieldMapAlertErrorTitle
        case fieldMapButtonOK // ^String.Titles.fieldMapButtonOK
        case fieldMapDetailGroup // ^String.Titles.fieldMapDetailGroup
        case fieldMapDetailDuration // ^String.Titles.fieldMapDetailDuration
        case fieldMapDetailPosition // ^String.Titles.fieldMapDetailPosition
        case fieldMapDetailColor // ^String.Titles.fieldMapDetailColor
        case fieldMapDetailNoGroup // ^String.Titles.fieldMapDetailNoGroup
        case fieldMapTagTitle // ^String.Titles.fieldMapTagTitle
        case fieldMapTagTitleNoNumber // ^String.Titles.fieldMapTagTitleNoNumber
        case fieldMapTagPosition // ^String.Titles.fieldMapTagPosition
        case fieldMapMenuInfo // ^String.Titles.fieldMapMenuInfo
        case fieldMapMenuHide // ^String.Titles.fieldMapMenuHide
        case fieldMapMenuShow // ^String.Titles.fieldMapMenuShow
        case fieldMapButtonSelect // ^String.Titles.fieldMapButtonSelect
        case fieldMapFormatDuration // ^String.Titles.fieldMapFormatDuration
        case fieldMapFormatPosition // ^String.Titles.fieldMapFormatPosition
        case fieldMapFormatTimeRange // ^String.Titles.fieldMapFormatTimeRange
        case videoPlayerScreenshotMissing // ^String.Titles.videoPlayerScreenshotMissing
        case videoPlayerScreenshotHelp // ^String.Titles.videoPlayerScreenshotHelp
        case videoPlayerVideoNotLoaded // ^String.Titles.videoPlayerVideoNotLoaded
        case videoPlayerErrorScreenshot // ^String.Titles.videoPlayerErrorScreenshot
        case analyticsTagDensityPeak // ^String.Titles.analyticsTagDensityPeak
        case analyticsTagDensityAverage // ^String.Titles.analyticsTagDensityAverage
        case analyticsLabelMostUsed // ^String.Titles.analyticsLabelMostUsed
        case analyticsChartNotAvailable // ^String.Titles.analyticsChartNotAvailable
        case analyticsLabelMostPopular // ^String.Titles.analyticsLabelMostPopular
        case analyticsChartDensityNotAvailable // ^String.Titles.analyticsChartDensityNotAvailable
        case analyticsIssueShortStamps // ^String.Titles.analyticsIssueShortStamps
        case analyticsIssueEmptyTimelines // ^String.Titles.analyticsIssueEmptyTimelines
        case analyticsStatsTimelineCount // ^String.Titles.analyticsStatsTimelineCount
        case analyticsStatsTags // ^String.Titles.analyticsStatsTags
        case analyticsStatsDurationTotal // ^String.Titles.analyticsStatsDurationTotal
        case analyticsTitleDistribution // ^String.Titles.analyticsTitleDistribution
        case collectionsFieldWidth // ^String.Titles.collectionsFieldWidth
        case collectionsFieldHeight // ^String.Titles.collectionsFieldHeight
        case collectionsTagsForMap // ^String.Titles.collectionsTagsForMap
        case collectionsGroupEmpty // ^String.Titles.collectionsGroupEmpty
        case CollectionsLabelGroupEmpty // ^String.Titles.CollectionsLabelGroupEmpty
        case collectionsTagEmpty // ^String.Titles.collectionsTagEmpty
        case collectionsLabelEmpty // ^String.Titles.collectionsLabelEmpty
        case collectionsEventEmpty // ^String.Titles.collectionsEventEmpty
        case collectionsLabelGroupName // ^String.Titles.collectionsLabelGroupName
        case collectionsButtonAddLabel // ^String.Titles.collectionsButtonAddLabel
        case collectionsLabelHotkeyUsed // ^String.Titles.collectionsLabelHotkeyUsed
        case collectionsLabelLabelGroups // ^String.Titles.collectionsLabelLabelGroups
        case collectionsTagUseWithMap // ^String.Titles.collectionsTagUseWithMap
        case collectionsTagMapHelp // ^String.Titles.collectionsTagMapHelp
        case collectionsTagHotkey // ^String.Titles.collectionsTagHotkey
        case collectionsTagNoHotkey // ^String.Titles.collectionsTagNoHotkey
        case collectionsTagTimeBefore // ^String.Titles.collectionsTagTimeBefore
        case collectionsTagTimeAfter // ^String.Titles.collectionsTagTimeAfter
        case collectionsTagTimeFormat // ^String.Titles.collectionsTagTimeFormat
        case collectionsDialogAddLabel // ^String.Titles.collectionsDialogAddLabel
        case collectionsButtonCancel // ^String.Titles.collectionsButtonCancel
        case collectionsButtonAdd // ^String.Titles.collectionsButtonAdd
        case collectionsDialogAddTimeEvent // ^String.Titles.collectionsDialogAddTimeEvent
        case collectionsLabelTagAssociations // ^String.Titles.collectionsLabelTagAssociations
        case collectionsButtonSaveChanges // ^String.Titles.collectionsButtonSaveChanges
        case timelineButtonDeleteTag // ^String.Titles.timelineButtonDeleteTag
        case timelineButtonEditLabels // ^String.Titles.timelineButtonEditLabels
        case timelineButtonDeleteTimeline // ^String.Titles.timelineButtonDeleteTimeline
        case fieldMapPickerLabelSelectTimelines // ^String.Titles.fieldMapPickerLabelSelectTimelines
        case fieldMapPickerNoTimelines // ^String.Titles.fieldMapPickerNoTimelines
        case fieldMapPickerTagsCount // ^String.Titles.fieldMapPickerTagsCount
        case fieldMapPickerLabelAllTags // ^String.Titles.fieldMapPickerLabelAllTags
        case fieldMapPickerNoPositionTags // ^String.Titles.fieldMapPickerNoPositionTags
        case fieldMapPickerTagsDisplayCount // ^String.Titles.fieldMapPickerTagsDisplayCount
        case tagLibraryAddingTag // ^String.Titles.tagLibraryAddingTag
        case tagLibraryNoTimeline // ^String.Titles.tagLibraryNoTimeline
        case tagLibraryDeleteTitle
        case fileManagerErrorDecoding
        case fileManagerErrorEncoding
        case videosViewTitleMatchInfo
        case videosViewFieldTeam1
        case videosViewFieldTeam2
        case videosViewFieldScore
        case videosViewFieldDateTime
        case videosViewButtonGuides
        case videosViewDialogRenameVideo
        case videosViewFieldFileName
        case fullControlExportFilmError
        case fullControlExportFilmSuccess
        case fullControlExportFilmErrorSave
        case fullControlExportPlaylistError
        case fullControlExportPlaylistSuccess
        case fullControlExportPlaylistErrorSave
        case fullControlExportNoSegments
        case fullControlExportErrorAsset
        case fullControlExportErrorJSON
        case fullControlExportErrorFullJSON
        case fullControlModeStandard
        case fullControlModeTagBased
        case fullControlModeHelp
        case fullControlButtonJSONSimple
        case fullControlButtonJSONFull
        case fullControlMenuExport
        case fullControlButtonExportTimeline
        case fullControlButtonExportAll
        case fullControlButtonExportTags
        case fullControlButtonExportEvents
        case fullControlButtonReport
        case fullControlButtonScreenshots
        case fullControlButtonMap
        case fullControlButtonAddTimeline
        case fullControlHelpAddTimeline
        case fullControlButtonTimelineZoomIn
        case fullControlButtonTimelineZoomOut
        case fullControlExportErrorStampNotFound
        case fullControlFileTimeline
        case fullControlFileEvent
        case fullControlFileTimelineFile
        case fullControlFileTagFile
        case fullControlFileEventFile
        case fullControlFileAllTimelinesFile
        case fullControlFileClipFile
        case fullControlFileEventClipFile
        case labelSheetInfoTagAdd
        case labelSheetErrorNoTimeline
        case labelSheetTimestamp

        case openButtonTitle
        case renameButtonTitle
        case renameLabelPlaceholder
        case editButtonTitle
        case helpRenameLabel
        
        case enterName
        case screenshotName
        case fileSavedSuccessfully
        case somethingWentWrong
        case photoEditor
        case enterLicense
        case buyLicense
        case license
        case cancel
        case confirm
        case pleaseEnterData
        case deviceIdentificationFailed
        case requestPreparationFailed
        case serverDataNotReceived
        case accountNotFound
        case serverResponseProcessingFailed
        case fileNotFound
        case decodingError
        case exportToImage
        case exportAnalyticsAsImage
        case pdfExportError
        case exportCompleted
        case imageSavedPath
        case scrollViewNotFound
        case scrollViewContentNotFound
        case failedToCreateImage
        case failedToSaveImage
        case creatingImage
        case exportAnalyticsToImage
        case layoutAnalyticsPng
        case layoutAnalytics
        case selectMapPositionForTag
        case tagLibrary
        case fieldMapVisualizationSettings
        case editScreenshot
        case createScreenshotAndOpenEditor
        case failedToLoadFieldMap
        case timelines
        case loadingScreenshots
        case editTimelineName
        case timelineName
        case exportAs
        case movie
        case playlist
        case availableEvents
        case selectEventForExport
        case selectTagForExport
        case inactiveTags
        case activeTags
        case selectCollectionWithFieldMap
        case collection
        case selectCollection
        case toggleTagsToChangePosition
        case time
        case position
        case noTags
        case deactivate
        case activate
        case fieldMapChange
        case fieldMapChangeWarning
        case resetPositions
        case savePositions
        case deletedFieldMap
        case deleteFieldMapWarning
        case deleteMap
        case addTagGroup
        case addLabelGroup
        case collectionName
        case updateCollection
        case saveCollection
        case saved
        case tagGroups
        case labelGroups
        case commonEvents
        case fieldMap
        case fieldMapSettings
        case addEvent
        case groupName
        case renameGroup
        case addGroup
        case tagsInGroup
        case addTag
        case tagName
        case renameTag
        case selectTimeEventForEditing
        case deleteFieldMap
        case failedToLoadImage
        case replaceImage
        case fieldMapNotSet
        case uploadFieldMapHint
        case uploadFieldMap
        case tagInfo
        case title
        case assign
        case hotkeyAlreadyUsed
        case labelInfo
        case relatedTags
        case eventInfo
        case deleteEvent
        case addNewTag
        case rrepeat
        case apply
        case selectFieldMapArea
        case closeWithoutApplying
        case events
        case labels
        case reset
        case noItemsAvailable
        case customCollection
        case editCollection
        case deleteCollection
        case collections
        case manageCustomTagCollections
        case createCollection
        case standardCollection
        case customCollections
        case delete
        case manageCollections
        case createNewCollection
        case confirmDeleteCollection
        case collapse
        case moreColors
        case reportGenerated
        case fieldMapVisualization
        case noCollectionsWithFieldMap
        case configureTagsOnFieldMap
        case visualize
        case visualizationMode
        case byTimelines
        case allTags
        case selectTags
        case noTagsWithPositionAvailable
        case editName
        case configureVisualization
        case displayMode
        case imageSaveError
        case snapshotFailed
        case momentVideo
        case videoUnavailable
        case tagsOverlap
        case tagsOverlapFormat
        case tagsDensityOverTime
        case tagsCount
        case videoTime
        case activeTagsCount
        case count
        case label
        case usageCount
        case tagsDurationStatistics
        case tag
        case minDuration
        case maxDuration
        case durationSeconds
        case durationStatisticsUnavailable
        case tagsDurationStatisticsByType
        case durationStatisticsDescription
        case generalStatistics
        case timelinesCount
        case totalTagsCount
        case labelStatistics
        case timelineStatistics
        case totalDuration
        case detectedIssues
        case itemsCount
        case myCollection
        case editingCollection
        case creatingNewCollection
        case subscriptionActiveUntil
        case subscriptionActive
        case videoUploadLimit
        case videoUploadLimitReached
        case renewLicense
        case midDuration
        case aIReports
        case standardCollections
        case collectionsTagIsInterval
        case collectionsTagIsIntervalHelp
        
        case video
        case exportReports
        case tools
        case screenshots
        case map
        case selectLabelForExport
        case skip
        case selectTagsForExport
        case noAvailableTags
        case done
        case selectLabelsForExport
        case noAvailableLabels
        case report
        case searchTagsAndEvents
        case showFavorites
        case noTagsToDisplay
        case tryChangingSearchQuery
        case all
        case tags
        case groups
        case search
        case selectElementFromLeftList
        case replace
        case failedToLoadFieldMapImage
        case fieldDimensions
        case useOnMap
        case basicInformation
        case name
        case description
        case color
        case timeSettings
        case additionalSettings
        case hotkeys
        case noRelatedTags
        case eventName
        case timeEventsDescription
        case information
        case labelsDescription
        case timeEventsDescription2
        case recent
        case favorites
        case searchVideos
        case noVideos
        case addFirstVideo
        case nothingFound
        case fillMatchInfo
        case enterTeam1Name
        case enterTeam2Name
        case enterScore
        case enterNewVideoName
        case enterNewName
        case removeFromFavorites
        case addToFavorites
        case screenshotsCount
        case deleteSelected
        case cancelSelection
        case deleteScreenshots
        case confirmDeleteScreenshots
        case addObject
        case clearAll
        case export
        case close
        case objects
        case templateCustomization
        case edgeColor
        case vertexColor
        case fillColor
        case lineType
        case showMisalignedVertices
        case warningColor
        case discrepancyThreshold
        case hide
        case show
        case selectFormation
        case noAvailableFormations
        case players
        case glowColor
        case radius
        case lineColor
        case exportImage
        case selectObjectType
        case configuration
        case save
        case generateAIReport
        case teamName
        case opponentTeamName
        case venue
        case matchDate
        case generate
        case hEX
        case clickTagToExport
        case selectLabelsForThisTag
        case discardChanges
        case changes
        
        case workingCopy
        case workingCopyDescription
        case applyChanges
        case unsaved
        
        case projectImportTitle
        case projectImportTeam1
        case projectImportTeam2
        case projectImportScore
        case projectImportCreationDate
        case projectImportTimelinesCount
        case projectImportCustomName
        case projectImportVideoBinding
        case projectImportChangeVideo
        case projectImportSelectVideoPrompt
        case projectImportSelectVideo
        case projectImportCreateWithoutVideo
        case projectImportCreateProject
        case selectNewVideo
        case warning
        case playlists
        case load
        case currentUnsaved
        case newPlaylist
        case tagsCountNew
        case savePlaylist
        case clearPlaylist
        case exportAsArchive
        case exportAsFilm
        case exportPlaylist
        case pause
        case play
        case playlistEmpty
        case dragTagsFromTimeline
        case deletePlaylistQuestion
        case confirmDeletePlaylist
        case drawingTools
        case clearDrawing
        case saveScreenshot
        case noVideoToPlay
        case addTagsToOrganizer
        case pressPlayButton
        case lineWidth
        case pixels
        case lineStyleDrawing
        case normal
        case dashed
        case selectColor
        case eraserWidth
        case drawingSettings
        case pencil
        case eraser
        case settings
        case screenshotSaved
        case errorCreatingScreenshot
        case view
        case simpleReport
        case timeline
        case duration
        case addToOrganizer
        case moveAll
        case addAll
        case filter
        case filterTimestamps
        case clearFilters
        case decreaseZoom
        case increaseZoom
        case filterTimestampsTitle
        case clear
        case timelineView
        case table
        case solid
        case dashedLine
        case square
        case diamond
        case line
        case trianglePlusOne
        case wFormation
        case pentagon
        case arrow
        case cross
        case hexagon
        case twoTwoTwo
        case star
        case doubleTriangle
        case threeTwoTwo
        case vFormation
        case flower
        case arrowFormation
        case threeThreeTwo
        case octagon
        case doubleDiamond
        case fortress
        case defense
        case attack
        case universal
        
        case exportProject
        case selectProjectSaveLocation
        case projectExportedSuccessfully
        case projectSavedToFile
        case exportError
        case failedToSaveProject
        case selectProjectFileForImport
        case importError
        case failedToLoadProject
        case videoUnavailableMessage
        case importCollection
        case selectCollectionFilePrompt
        case importingCollection
        case selectCollectionFileButton
        case selectFile
        case selectCollectionFile
        case selectCollectionFileMessage
        case selectVideoFile
        case selectNewVideoFileMessage
        case unknownError
        case exporting
        case selectPlaylist
        case savePlaylistTitle
        case playlistName
        case playlistInfo
        case error
        case playlistAlreadyExists
        case labelsNone
        case labelsPrefix
        case eventsNone
        case eventsPrefix
        case timeAndMoment
        case playTag
        case removeFromOrganizer
        
        case groupNameLabel
        case informationLabel
        case commonEventsDescription
        case commonEventsDescriptionExtended
        case labelsDescriptionText
        case rebindVideo
        case timestampsTable
        case noTimestamps
        case tryChangeFilters
        case hideNumber
        case showNumber
        case zoneBetweenObjects
        case lineBetweenObjects
        case objectHighlight
        case simpleZone
        case testCollection
        case testTags
        case testTag
        case testTagDescription
        case testLabels
        case testLabel
        case testLabelDescription
        case testEvent
        case exportCollectionTitle
        case selectCollectionSaveLocation
        case timestampsCount
    }
    
}

extension RawRepresentable {
    
    func format(_ args: CVarArg...) -> String {
        let format = ^self
        return String(format: format, arguments: args)
    }
    
}

prefix operator ^
prefix func ^<Type: RawRepresentable> (_ value: Type) -> String {
    if let raw = value.rawValue as? String {
        let key = raw.capitalizeFirstLetter()
        return NSLocalizedString(key, comment: "")
    }
    return ""
}
