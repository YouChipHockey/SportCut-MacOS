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
        case videoMirrorWindowTitle
        case videoMirrorToggleHelp
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
        case collectionsTagsCount // ^String.Titles.collectionsTagsCount
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
        case collectionsTagLayout // ^String.Titles.collectionsTagLayout
        case collectionsDialogAddLabel // ^String.Titles.collectionsDialogAddLabel
        case collectionsButtonCancel // ^String.Titles.collectionsButtonCancel
        case collectionsButtonAdd // ^String.Titles.collectionsButtonAdd
        case collectionsDialogAddTimeEvent // ^String.Titles.collectionsDialogAddTimeEvent
        case collectionsLabelTagAssociations // ^String.Titles.collectionsLabelTagAssociations
        case collectionsButtonSaveChanges // ^String.Titles.collectionsButtonSaveChanges
        case timelineButtonDeleteTag // ^String.Titles.timelineButtonDeleteTag
        case timelineButtonEditLabels // ^String.Titles.timelineButtonEditLabels
        case timelineButtonEditTimeEvents // ^String.Titles.timelineButtonTimeEvents
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
        case fullControlButtonXML
        case fullControlMenuExport
        case fullControlButtonExportTimeline
        case fullControlButtonExportAll
        case fullControlButtonExportDrawings
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
        case exportWithDrawings
        case exportWithDrawingsHelp
        case exportAddEpisodeNumbering
        case exportAddTagAndLabels
        case exportAddComment
        case editorTextBoxDefaultText
        case aiReportTitle
        case aiReportFileNameFormat
        case aiReportSaveError
        case fullControlLabelStandard
        case fullControlLabelZoom
        case fullControlMenuJSON
        case fullControlExportSimpleJsonFileName
        case fullControlExportFullJsonFileName
        case fullControlExportXmlFileName
        case fullControlAiReportErrorGeneration
        case fullControlErrorNoServerData
        case fullControlErrorServer
        case fullControlErrorEncodingRequest
        case fullControlSimpleReportErrorGeneration
        case fullControlErrorDataToHtml
        case fullControlExportJsonSaveError
        case fullControlExportFullJsonSaveError
        case fullControlScreenshotGoToHelp
        case fullControlEdit
        case fullControlEditBoundTags
        case fullControlEditBoundTagsTitle
        case fullControlScreenshotLabel
        case fullControlNoTagsForBinding
        case fullControlTimelineLabel
        case drawingsTimelineName
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
        case renameEvent
        case eventName
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
        case transparentBackground
        case opaqueBackground
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
        case projectImportChooseFormatTitle
        case projectImportChooseFormatMessage
        case projectImportSportcutFormat
        case projectImportSportcodeXmlFormat
        case selectSportcodeXmlForImport
        case xmlImportNoInstancesError
        case xmlImportParseFailedError
        case xmlImportCollectionDisplayName
        case xmlImportTagGroupName
        case xmlImportNotesLabelGroupName
        case xmlImportTimelineLineName
        case videoMarkupToastTagAdded
        case videoMarkupToastIntervalRecording
        case videoMarkupToastIntervalSaved
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
        case lineWithArrow
        case curvedArrow
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
        case renamePlaylist
        case newName
        case rename
        
        // Video Download from URL
        case addVideoFromURL
        case downloadVideoFromURL
        case downloadVideoFromURLDescription
        case videoURL
        case enterVideoURL
        case videoFormat
        case fetchingVideoInfo
        case videoTitle
        case selectQuality
        case downloadingVideo
        case videoDownloaded
        case videoDownloadedDescription
        case fetchFormats
        case downloadButtonTitle
        case continueButtonTitle
        case tryAgain
        case useServerVideoName
        case useServerVideoNameDescription
        
        // Downloads Folder Permissions
        case selectDownloadsFolderMessage
        case grantAccessButtonTitle
        case downloadsFolderAccessRequired
        case downloadsFolderAccessDescription
        case openSystemSettings
        case downloadsFolderAccessGranted
        case checkPermissions
        
        // Editor (drawing / video player)
        case editorCursor
        case editorTelestration
        case editorShapes
        case editorTextBox
        case undo
        case editorCursorMode
        case editorSelectMode
        case editorCreatingFormat
        case editorVerticesCount
        case editorBack
        case editorConfigurationShapeFormat
        case editorEditShapeFormat
        case editorStrokeColor
        case editorStrokeWidth
        case editorEditTextBox
        case editorTextLabel
        case editorTextColor
        case editorFontSize
        case editorFont
        case editorBackground
        case editorBorderColor
        case editorBorderWidth
        case editorAddPoint
        case editorModeInParentheses
        case editorCurveHeight
        case editorExportDurationLabel
        case editorSaveToTag
        case editorScreenshotNamePlaceholder
        case editorTitle
        case editorSelectTagsForScreenshot
        case editorTimeLabelFormat
        case editorNoTagsAtMoment
        case editorAddPointModeHelp
        case copy
        case paste
        
        // Editor shape names (ShapeType.displayName)
        case editorShapeTriangle
        case editorShapeSquare
        case editorShapeRectangle
        case editorShapeCircle
        case editorShapeStar
        case editorShapeHexagon
        
        // Live Stream
        case recordVideo
        case liveStreamTitle
        case liveStreamDescription
        case liveStreamVideoSource
        case liveStreamAudioSource
        case liveStreamQuality
        case liveStreamNoVideoDevices
        case liveStreamNoAudioDevices
        case liveStreamNoAudio
        case liveStreamSelectDeviceFirst
        case liveStreamStartButton
        case liveStreamConfigError
        case liveStreamMatchInfo
        case liveStreamStartRecording
        case liveStreamStopBroadcast
        case liveStreamContinueBroadcast
        case liveStreamPausedLabel
        case liveStreamBroadcastPaused
        case liveStreamPreloadedVideo
        case liveStreamPreloadedVideoHint
        case liveStreamPickPreloadFile
        case appendToVideo
        
        // Data Sync & Backup
        case dataManagementTitle
        case dataManagementBackupSystemInfo
        case dataManagementBackupSystemDescription
        case dataManagementDocumentsTitle
        case dataManagementDocumentsDescription
        case dataManagementDocumentsHelp
        case dataManagementApplicationSupportTitle
        case dataManagementApplicationSupportDescription
        case dataManagementApplicationSupportHelp
        case dataManagementBackupNote
        case dataManagementRestoreFromBackup
        case dataManagementRestoreFromBackupDescription
        case dataManagementCreateBackup
        case dataManagementCreateBackupDescription
        case dataManagementCheckOrphanedTimelines
        case dataManagementCheckOrphanedTimelinesDescription
        case dataManagementDeleteAllData
        case dataManagementDeleteAllDataDescription
        case dataManagementProcessing
        case dataManagementRestoreConfirmationTitle
        case dataManagementRestoreConfirmationMessage
        case dataManagementDeleteConfirmationTitle
        case dataManagementDeleteConfirmationMessage
        case dataManagementBackupCreatedSuccess
        case dataManagementRestoreSuccess
        case dataManagementDeleteSuccess
        case dataManagementNoOrphanedTimelines
        case dataManagementAllTimelinesLinked
        
        // Orphaned Timelines Recovery
        case orphanedTimelinesTitle
        case orphanedTimelinesFound
        case orphanedTimelinesInstructions
        case orphanedTimelinesSkipAll
        case orphanedTimelinesRestoreSelected
        case orphanedTimelinesRestoring
        case orphanedTimelinesRestoreSuccess
        case orphanedTimelinesRestoreSuccessMessage
        case orphanedTimelinesSelectVideo
        case orphanedTimelinesChangeVideo
        case orphanedTimelinesDelete
        case orphanedTimelinesDeleteConfirmationTitle
        case orphanedTimelinesDeleteConfirmationMessage
        case orphanedTimelinesDeleteHelp
        case orphanedTimelinesUnknownVideo
        case orphanedTimelinesSaved
        case orphanedTimelinesTimelineSingular
        case orphanedTimelinesTimelinePlural24
        case orphanedTimelinesTimelinePlural5Plus
        case orphanedTimelinesStampsSingular
        case orphanedTimelinesStampsPlural24
        case orphanedTimelinesStampsPlural5Plus
        
        // Data Sync Logs (for print statements - optional)
        case dataSyncStartSync
        case dataSyncNoDataInDocuments
        case dataSyncRestoringFromBackup
        case dataSyncDataExists
        case dataSyncCheckingDifferences
        case dataSyncDifferencesFound
        case dataSyncDataIdentical
        case dataSyncCreatingBackup
        case dataSyncBackupCreated
        case dataSyncRestoringData
        case dataSyncDataRestored
        case dataSyncDeletingAllData
        case dataSyncAllDataDeleted
        case dataSyncOrphanedTimelinesFound
        case dataSyncRestoringTimeline
        case dataSyncNoVideoData
        case dataSyncTimelineRestored
        case dataSyncTimelineRestoreError
        case dataSyncTimelineDeleted
        
        // SportCut
        case sportCutShowHidePlaylists
        case sportCutShowHideEvents
        case sportCutFullscreen
        case sportCutSelectEventToPlay
        case sportCutSeekBack10
        case sportCutSeekBack5
        case sportCutSeekBack2
        case sportCutSeekForward2
        case sportCutSeekForward5
        case sportCutSeekForward10
        case sportCutCreateDrawing
        case sportCutHideEventWatermark
        case sportCutShowEventWatermark
        case sportCutHideComments
        case sportCutShowComments
        case sportCutDrawing
        case sportCutDeletePlaylistQuestion
        case sportCutNewPlaylistHelp
        case sportCutExportPlaylists
        case sportCutNewGroupHelp
        case sportCutNoPlaylists
        case sportCutDragEventsHint
        case sportCutDragToDelete
        case sportCutNewPlaylist
        case sportCutNameOptional
        case sportCutNewGroup
        case sportCutGroupNamePlaceholder
        case sportCutRenamePlaylist
        case sportCutNewNamePlaceholder
        case sportCutShowPlaylist
        case sportCutHidePlaylist
        case sportCutMoveUp
        case sportCutMoveDown
        case sportCutMoveLeft
        case sportCutMoveRight
        case sportCutPlayAsFilm
        case sportCutPlayAction
        case sportCutDuplicate
        case sportCutRenameAction
        case sportCutEditComment
        case sportCutAddComment
        case sportCutShowEvent
        case sportCutHideEvent
        case sportCutDeleteFromPlaylist
        case sportCutEditDrawing
        case sportCutDeleteDrawing
        case sportCutDeleteGroup
        case sportCutBulkSelectedCount
        case sportCutBulkTotalDuration
        case sportCutBulkClearSelection
        case sportCutComment
        case sportCutSessionNotFound
        case sportCutSelectProjectForTimeline
        case sportCutAllTab
        case sportCutDeleteFromSession
        case sportCutAddAll
        case sportCutFilterTitle
        case sportCutAddVideoOrProject
        case sportCutAddToPlaylist
        case sportCutAddSources
        case sportCutAddMarkupProject
        case sportCutAddVideoFile
        case sportCutCurrentSources
        case sportCutEventsCount
        case sportCutSelectVideoFiles
        case sportCutCreateSession
        case sportCutAddProjectsDescription
        case sportCutSessionName
        case sportCutEnterName
        case sportCutMarkupProjects
        case sportCutAddProject
        case sportCutNoAddedProjects
        case sportCutVideoFiles
        case sportCutAddVideo
        case sportCutNoAddedVideos
        case sportCutCreate
        case sportCutDefaultGroupName
        case sportCutSelectProjects
        case sportCutNoAvailableProjects
        case sportCutDeleteSessionQuestion
        case sportCutSearchSessions
        case sportCutNewSession
        case sportCutNoSessions
        case sportCutCreateSessionHint
        case sportCutCreateSessionButton
        case sportCutOpen
        case sportCutSessionWillBeDeleted
        case sportCutEventsTable
        case sportCutNoEvents
        case sportCutProjectColumn
        case sportCutTimelineColumn
        case sportCutTagColumn
        case sportCutStartColumn
        case sportCutEndColumn
        case sportCutDurationColumn
        case sportCutLabelsColumn
        case sportCutEventsColumn
        case sportCutFilters
        case sportCutReset
        case sportCutTagGroups
        case sportCutTags
        case sportCutLabelGroups
        case sportCutLabels
        case sportCutCommonEvents
        case sportCutExportTitle
        case sportCutExportType
        case sportCutSelectPlaylists
        case sportCutSelectAll
        case sportCutAddWatermark
        case sportCutExportProgress
        case sportCutExportAction
        case sportCutTimelinesAndEvents
        case sportCutLoading
        
        // Free Tag Mode
        case freeTagModeGrouped
        case freeTagModeFree
        case freeTagModeNotConfiguredTitle
        case freeTagModeNotConfiguredMessage
        case freeTagModeDisplay
        
        case sportCutGroupPrefix
        case sportCutSessionPrefix
        case sportCutAddCount

        // SportCut Viewing Mode
        case sportCutWindowTitlePrefix
        case sportCutExportTypeClips
        case sportCutExportTypeFilm
        case sportCutExportTypeFilmPerPlaylist
        case sportCutSortTimeAsc
        case sportCutSortTimeDesc
        case sportCutSortDurationAsc
        case sportCutSortDurationDesc
        case sportCutSortTagNameAsc
        case sportCutSortProjectAsc
        case sportCutPaneMarkup
        case sportCutPaneTable
        case sportCutSortOriginal
        case sportCutSortTimelinesAsc
        case sportCutSortTimelinesDesc
        case sportCutTagsPlaylistPrefix

        // Viewing Mode UI
        case viewingSelectedTags
        case viewingTotalDuration
        case viewingNewSession
        case viewingToExistingSession
        case viewingDeselectAll
        case viewingOpenInMode
        case viewingAddSelectedToPlaylist
        case viewingLiveModeHelp
        case viewingReviewLabel
        case viewingReviewHelp
        case viewingSortReset
        case viewingSortAlphaAsc
        case viewingSortAlphaDesc
        case viewingSortTagCountDesc
        case viewingSortTagCountAsc
        case viewingSortLastTagChronological
        case viewingSortLastTagReverse
        case viewingTimelineFiltersHelp
        case viewingViewMoment
        case viewingAddComment
        case viewingEditComment
        case viewingDeleteComment

        // MomentViewer
        case momentDurationLabel
        case momentScaleLabel
        case momentScaleAccessibility
        case momentEventsPrefix
        case momentLabelsPrefix
        case momentWindowTitlePrefix

        // ReviewVideo
        case reviewLoadingRecording
        case reviewBadgeUpdated
        case reviewEditorButton
        case reviewEditorHelp
        case reviewPlayPauseHelp
        case reviewWindowTitle

        // StampComment
        case stampCommentTitle

        // Analytics
        case analyticsTagCount

        // VideoPlayer
        case videoHistoryToggle
        case videoHistoryHelp
        case videoBroadcastPauseHelp
        case videoBroadcastResumeHelp
        case videoBroadcastStopHelp
        case videoCloseScreenshotHelp
        case videoTelestrationHelp
        case videoOpenEditorHelp
        case videoZoomOutHelp
        case videoZoomInHelp
        case videoZoomResetHelp

        // MomentMiniTimeline
        case momentScrollLeftHelp
        case momentScrollRightHelp

        // ViewerTimeline
        case viewerAddAllTagsHelp
        case viewerSwitchModeHelp
        case viewerFilterStampsHelp
        case viewerClearFiltersHelp

        // CurvedArrow
        case curvedArrowHeightLabel

        // TagFreeLayoutEditor
        case freeLayoutTitle
        case freeLayoutCanvasSettings
        case freeLayoutSelectElement
        case freeLayoutShowGrid
        case freeLayoutSnapToGrid
        case freeLayoutSectionShape
        case freeLayoutSectionFill
        case freeLayoutOpacity
        case freeLayoutTransparent
        case freeLayoutOpaque
        case freeLayoutSectionStroke
        case freeLayoutColor
        case freeLayoutThickness
        case freeLayoutStrokeSolid
        case freeLayoutStrokeDashed
        case freeLayoutSectionText
        case freeLayoutShowLabel
        case freeLayoutFontSize
        case freeLayoutSectionGeometry
        case freeLayoutCornerRadius
        case freeLayoutLockAspect
        case freeLayoutSectionShadow
        case freeLayoutShadowEnabled
        case freeLayoutShadowIntensity
        case freeLayoutSectionOrder
        case freeLayoutSectionAlignment
        case freeLayoutCenterHorizontal
        case freeLayoutCenterVertical

        // Main Tabs
        case mainTabMarkup
        case mainTabViewing

        // Tools Menu
        case toolsExportMarkup
        case toolsExportMarkupJsonFull
        case toolsExportMarkupJsonSimple
        case toolsExportCuts
        case toolsReport
        case toolsReportSimple
        case toolsReportAdvanced

        // Version Alert
        case versionOutdatedMessage
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
