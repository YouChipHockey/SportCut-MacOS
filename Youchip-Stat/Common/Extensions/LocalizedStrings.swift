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
        case video
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
