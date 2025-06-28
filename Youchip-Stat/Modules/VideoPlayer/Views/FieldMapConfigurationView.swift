//
//  FieldMapConfigurationView.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 6/9/25.
//


import SwiftUI

struct FieldMapConfigurationView: View {
    
    @State private var collections: [CollectionBookmark] = []
    @State private var selectedCollection: CollectionBookmark? = nil
    @State private var fieldImage: NSImage? = nil
    @State private var imageSize: CGSize = .zero
    @State private var activeTags: [TagOnMap] = []
    @State private var inactiveTags: [TagOnMap] = []
    @State private var fieldDimensions: (width: Double, height: Double) = (0, 0)
    @State private var isDraggingActive = false
    @State private var draggedTag: TagOnMap? = nil
    @State private var isMovingOnMap = false
    @State private var selectedTagForMove: TagOnMap? = nil
    @State private var contextMenuTag: TagOnMap? = nil
    @State private var showContextMenu = false
    @State private var contextMenuPosition = CGPoint.zero
    @ObservedObject private var timelineData = TimelineDataManager.shared
    
    var body: some View {
        VStack {
            collectionSelectionSection
            
            if selectedCollection != nil {
                Divider()
                
                if let image = fieldImage {
                    mapWithTagsSection(image)
                } else {
                    Text(^String.Titles.fieldMapLoading)
                        .frame(height: 300)
                }
                
                Divider()
                
                HStack(alignment: .top, spacing: 0) {
                    tagsListView(title: ^String.Titles.activeTags, tags: activeTags, isActive: true)
                        .frame(maxWidth: .infinity)
                    tagsListView(title: ^String.Titles.inactiveTags, tags: inactiveTags, isActive: false)
                        .frame(maxWidth: .infinity)
                }
                .padding()
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            loadCollections()
        }
        .onChange(of: selectedCollection) { _ in
            if let collection = selectedCollection {
                loadFieldImageAndTagsForCollection(collection)
            } else {
                clearFieldData()
            }
        }
        .overlay(
            Group {
                if showContextMenu, let tag = contextMenuTag {
                    tagContextMenu(tag)
                        .position(contextMenuPosition)
                }
            }
        )
    }
    
    private var collectionSelectionSection: some View {
        VStack(alignment: .leading) {
            Text(^String.Titles.selectCollectionWithFieldMap)
                .font(.headline)
            
            Picker(selection: $selectedCollection, label: Text(^String.Titles.collection)) {
                Text(^String.Titles.selectCollection).tag(nil as CollectionBookmark?)
                
                ForEach(collectionsWithFieldMap, id: \.name) { collection in
                    Text(collection.name).tag(collection as CollectionBookmark?)
                }
            }
            .frame(width: 300)
        }
        .padding(.bottom)
    }
    
    private func mapWithTagsSection(_ image: NSImage) -> some View {
        MapSectionContainer(
            image: image,
            imageSize: $imageSize,
            activeTags: activeTags,
            isMovingOnMap: $isMovingOnMap,
            selectedTagForMove: $selectedTagForMove,
            contextMenuTag: $contextMenuTag,
            showContextMenu: $showContextMenu,
            contextMenuPosition: $contextMenuPosition,
            fieldDimensions: fieldDimensions,
            onPositionUpdate: updateTagPosition
        )
    }
    
    private struct MapSectionContainer: View {
        let image: NSImage
        @Binding var imageSize: CGSize
        let activeTags: [TagOnMap]
        @Binding var isMovingOnMap: Bool
        @Binding var selectedTagForMove: TagOnMap?
        @Binding var contextMenuTag: TagOnMap?
        @Binding var showContextMenu: Bool
        @Binding var contextMenuPosition: CGPoint
        let fieldDimensions: (width: Double, height: Double)
        let onPositionUpdate: (TagOnMap, CGPoint) -> Void
        
        var body: some View {
            VStack {
                Text(^String.Titles.toggleTagsToChangePosition)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.bottom, 4)
                
                mapContent
            }
            .padding()
        }
        
        private var mapContent: some View {
            ZStack(alignment: .center) {
                GeometryReader { geo in
                    ZStack {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .background(
                                GeometryReader { imageGeo -> Color in
                                    DispatchQueue.main.async {
                                        let imageAspect = image.size.width / image.size.height
                                        let containerAspect = geo.size.width / geo.size.height
                                        
                                        if imageAspect > containerAspect {
                                            let width = geo.size.width
                                            let height = width / imageAspect
                                            imageSize = CGSize(width: width, height: height)
                                        } else {
                                            let height = geo.size.height
                                            let width = height * imageAspect
                                            imageSize = CGSize(width: width, height: height)
                                        }
                                    }
                                    return Color.clear
                                }
                            )
                            .overlay(
                                TagsOverlay(
                                    activeTags: activeTags,
                                    isMovingOnMap: $isMovingOnMap,
                                    selectedTagForMove: $selectedTagForMove,
                                    contextMenuTag: $contextMenuTag,
                                    showContextMenu: $showContextMenu,
                                    contextMenuPosition: $contextMenuPosition,
                                    fieldDimensions: fieldDimensions,
                                    imageSize: imageSize
                                )
                            )
                            .overlay(
                                Group {
                                    if isMovingOnMap {
                                        MapTapHandlerView(
                                            isMovingOnMap: $isMovingOnMap,
                                            selectedTagForMove: $selectedTagForMove,
                                            showContextMenu: $showContextMenu,
                                            imageSize: imageSize,
                                            fieldDimensions: fieldDimensions,
                                            onTagPositionUpdate: onPositionUpdate
                                        )
                                    }
                                }
                            )
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    }
                }
            }
            .frame(maxHeight: .infinity)
            .background(Color.black.opacity(0.05))
            .cornerRadius(8)
            .contentShape(Rectangle())
        }
    }
    
    private struct ImageWithSizeCapture: View {
        let image: NSImage
        @Binding var imageSize: CGSize
        
        var body: some View {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .background(
                    GeometryReader { geo in
                        Color.clear.onAppear {
                            imageSize = geo.size
                        }
                    }
                )
        }
    }
    
    private struct TagsOverlay: View {
        let activeTags: [TagOnMap]
        @Binding var isMovingOnMap: Bool
        @Binding var selectedTagForMove: TagOnMap?
        @Binding var contextMenuTag: TagOnMap?
        @Binding var showContextMenu: Bool
        @Binding var contextMenuPosition: CGPoint
        let fieldDimensions: (width: Double, height: Double)
        let imageSize: CGSize
        
        var body: some View {
            ZStack {
                ForEach(activeTags, id: \.self) { tag in
                    TagMarker(
                        tag: tag,
                        isMovingOnMap: $isMovingOnMap,
                        selectedTagForMove: $selectedTagForMove,
                        contextMenuTag: $contextMenuTag,
                        showContextMenu: $showContextMenu,
                        contextMenuPosition: $contextMenuPosition,
                        fieldDimensions: fieldDimensions,
                        imageSize: imageSize
                    )
                }
            }
        }
    }
    
    private struct TagMarker: View {
        let tag: TagOnMap
        @Binding var isMovingOnMap: Bool
        @Binding var selectedTagForMove: TagOnMap?
        @Binding var contextMenuTag: TagOnMap?
        @Binding var showContextMenu: Bool
        @Binding var contextMenuPosition: CGPoint
        let fieldDimensions: (width: Double, height: Double)
        let imageSize: CGSize
        
        @State private var currentPosition: CGPoint = .zero
        
        var body: some View {
            let screenPosition = fieldPositionToScreenPosition(
                tag.position,
                fieldWidth: CGFloat(fieldDimensions.width),
                fieldHeight: CGFloat(fieldDimensions.height),
                imageWidth: imageSize.width,
                imageHeight: imageSize.height
            )
            
            return ZStack {
                Circle()
                    .fill(Color(hex: tag.colorHex))
                    .frame(width: 18, height: 18)
                
                Text("\(tag.number)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white)
                
                Circle()
                    .stroke(Color.white, lineWidth: 2)
                    .frame(width: 20, height: 20)
            }
            .position(screenPosition)
            .id("\(tag.id)-\(tag.position.x)-\(tag.position.y)")
            .onAppear {
                currentPosition = tag.position
            }
            .onChange(of: tag.position) { newPosition in
                currentPosition = newPosition
            }
            .onTapGesture {
                if isMovingOnMap && selectedTagForMove?.id == tag.id {
                    isMovingOnMap = false
                    selectedTagForMove = nil
                } else {
                    isMovingOnMap = true
                    selectedTagForMove = tag
                }
            }
            .onLongPressGesture {
                contextMenuTag = tag
                contextMenuPosition = screenPosition
                showContextMenu = true
            }
            .contextMenu {
                Text("\(^String.Titles.fieldMapTagTitleNoNumber) \(tag.name)")
                Text("\(^String.Titles.time): \(tag.timeStart) - \(tag.timeFinish)")
                Text("\(^String.Titles.fieldMapDetailPosition) (\(Int(tag.position.x)), \(Int(tag.position.y)))")
            }
        }
        
        private func fieldPositionToScreenPosition(
            _ fieldPosition: CGPoint,
            fieldWidth: CGFloat,
            fieldHeight: CGFloat,
            imageWidth: CGFloat,
            imageHeight: CGFloat
        ) -> CGPoint {
            let fieldAspect = fieldWidth / fieldHeight
            let imageAspect = imageWidth / imageHeight
            
            var scaledWidth = imageWidth
            var scaledHeight = imageHeight
            var xOffset: CGFloat = 0
            var yOffset: CGFloat = 0
            
            if fieldAspect > imageAspect {
                scaledHeight = imageWidth / fieldAspect
                yOffset = (imageHeight - scaledHeight) / 2
            } else {
                scaledWidth = imageHeight * fieldAspect
                xOffset = (imageWidth - scaledWidth) / 2
            }
            let x = (fieldPosition.x / fieldWidth) * scaledWidth + xOffset
            let y = (fieldPosition.y / fieldHeight) * scaledHeight + yOffset
            
            return CGPoint(x: x, y: y)
        }
    }
    
    private func tagsListView(title: String, tags: [TagOnMap], isActive: Bool) -> some View {
        TagsListContainer(title: title, tags: tags, isActive: isActive,
                          onToggleStatus: toggleTagActiveStatus)
    }
    
    private struct TagsListContainer: View {
        let title: String
        let tags: [TagOnMap]
        let isActive: Bool
        let onToggleStatus: (TagOnMap, Bool) -> Void
        
        var body: some View {
            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .font(.headline)
                
                if tags.isEmpty {
                    EmptyTagsView()
                } else {
                    TagsScrollView(
                        tags: tags,
                        isActive: isActive,
                        onToggleStatus: onToggleStatus
                    )
                }
            }
            .padding(.horizontal, 10)
        }
    }
    
    private struct EmptyTagsView: View {
        var body: some View {
            Text(^String.Titles.noTags)
                .foregroundColor(.secondary)
                .padding()
        }
    }
    
    private struct TagsScrollView: View {
        let tags: [TagOnMap]
        let isActive: Bool
        let onToggleStatus: (TagOnMap, Bool) -> Void
        
        var body: some View {
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(tags) { tag in
                        TagRow(
                            tag: tag,
                            isActive: isActive,
                            onToggleStatus: onToggleStatus
                        )
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(height: 200)
            .background(Color.white.opacity(0.2))
            .cornerRadius(8)
        }
    }
    
    private struct TagRow: View {
        let tag: TagOnMap
        let isActive: Bool
        let onToggleStatus: (TagOnMap, Bool) -> Void
        
        var body: some View {
            HStack {
                Toggle("", isOn: Binding(
                    get: { isActive },
                    set: { newValue in
                        onToggleStatus(tag, newValue)
                    }
                ))
                .labelsHidden()
                .toggleStyle(CheckboxToggleStyle())
                
                Circle()
                    .fill(Color(hex: tag.colorHex))
                    .frame(width: 10, height: 10)
                
                Text("\(tag.name) (№\(tag.number))")
                    .lineLimit(1)
                    .truncationMode(.tail)
                
                Spacer()
                
                Text(tag.timeStart)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(8)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(4)
            .contextMenu {
                Text("\(^String.Titles.fieldMapTagTitleNoNumber) \(tag.name)")
                Text("\(^String.Titles.time): \(tag.timeStart) - \(tag.timeFinish)")
                
                Divider()
                
                Button(isActive ? ^String.Titles.deactivate : ^String.Titles.activate) {
                    onToggleStatus(tag, !isActive)
                }
            }
        }
    }
    
    private func tagContextMenu(_ tag: TagOnMap) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(^String.Titles.fieldMapTagTitleNoNumber) \(tag.name)")
                .font(.headline)
            Text("\(^String.Titles.time): \(tag.timeStart) - \(tag.timeFinish)")
            
            Divider()
            
            Button(^String.Titles.closeButtonTitle) {
                showContextMenu = false
            }
        }
        .padding()
        .background(Color.white)
        .cornerRadius(8)
        .shadow(radius: 5)
        .onTapGesture {
            showContextMenu = false
        }
    }
    
    private var collectionsWithFieldMap: [CollectionBookmark] {
        collections.filter { collection in
            let collectionManager = CustomCollectionManager()
            return collectionManager.loadCollectionFromBookmarks(named: collection.name) &&
            collectionManager.playField != nil &&
            collectionManager.playField?.imageBookmark != nil
        }
    }
    
    private func loadCollections() {
        collections = UserDefaults.standard.getCollectionBookmarks()
    }
    
    private func loadFieldImageAndTagsForCollection(_ collection: CollectionBookmark) {
        let collectionManager = CustomCollectionManager()
        
        guard collectionManager.loadCollectionFromBookmarks(named: collection.name),
              let playField = collectionManager.playField,
              let imageBookmark = playField.imageBookmark else {
            clearFieldData()
            return
        }
        fieldDimensions = (playField.width, playField.height)
        loadFieldImage(from: imageBookmark)
        loadTagsForCollection(collection)
    }
    
    private func loadFieldImage(from imageBookmark: Data) {
        do {
            var isStale = false
            let imageURL = try URL(resolvingBookmarkData: imageBookmark, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale)
            
            guard imageURL.startAccessingSecurityScopedResource() else {
                fieldImage = nil
                return
            }
            
            defer {
                imageURL.stopAccessingSecurityScopedResource()
            }
            
            if let image = NSImage(contentsOf: imageURL) {
                fieldImage = image
            } else {
                fieldImage = nil
            }
        } catch {
            print("Error loading field image: \(error)")
            fieldImage = nil
        }
    }
    
    private func loadTagsForCollection(_ collection: CollectionBookmark) {
        let collectionManager = CustomCollectionManager()
        guard collectionManager.loadCollectionFromBookmarks(named: collection.name) else {
            clearTagsData()
            return
        }
        var allPositionedTags = timelineData.lines.flatMap { line in
            line.stamps.compactMap { stamp -> TagOnMap? in
                guard let position = stamp.position,
                      isTagFromCollection(stamp.idTag, collection: collection) else {
                    return nil
                }
                
                return TagOnMap(
                    id: stamp.id.uuidString,
                    stampId: stamp.id,
                    lineId: line.id,
                    name: stamp.label,
                    colorHex: stamp.colorHex,
                    timeStart: stamp.timeStart,
                    timeFinish: stamp.timeFinish,
                    position: position,
                    isActiveForMapView: stamp.isActiveForMapView ?? false
                )
            }
        }
        for i in 0..<allPositionedTags.count {
            allPositionedTags[i].number = i + 1
        }
        activeTags = allPositionedTags.filter { $0.isActiveForMapView }
        inactiveTags = allPositionedTags.filter { !$0.isActiveForMapView }
    }
    
    private func isTagFromCollection(_ tagId: String, collection: CollectionBookmark) -> Bool {
        let collectionManager = CustomCollectionManager()
        guard collectionManager.loadCollectionFromBookmarks(named: collection.name) else {
            return false
        }
        
        return collectionManager.tags.contains { $0.id == tagId }
    }
    
    private func clearFieldData() {
        fieldImage = nil
        fieldDimensions = (0, 0)
        clearTagsData()
    }
    
    private func clearTagsData() {
        activeTags = []
        inactiveTags = []
    }
    
    private func toggleTagActiveStatus(_ tag: TagOnMap, isActive: Bool) {
        for lineIndex in timelineData.lines.indices {
            if timelineData.lines[lineIndex].id == tag.lineId {
                for stampIndex in timelineData.lines[lineIndex].stamps.indices {
                    if timelineData.lines[lineIndex].stamps[stampIndex].id == tag.stampId {
                        timelineData.lines[lineIndex].stamps[stampIndex].isActiveForMapView = isActive
                        updateLocalTagLists(tag, isActive: isActive)
                        timelineData.updateTimelines()
                        return
                    }
                }
            }
        }
    }
    
    private func updateLocalTagLists(_ tag: TagOnMap, isActive: Bool) {
        let updatedTag = TagOnMap(
            id: tag.id,
            stampId: tag.stampId,
            lineId: tag.lineId,
            name: tag.name,
            colorHex: tag.colorHex,
            timeStart: tag.timeStart,
            timeFinish: tag.timeFinish,
            position: tag.position,
            isActiveForMapView: isActive,
            number: tag.number
        )
        
        if isActive {
            inactiveTags.removeAll { $0.id == tag.id }
            activeTags.append(updatedTag)
        } else {
            activeTags.removeAll { $0.id == tag.id }
            inactiveTags.append(updatedTag)
        }
    }
    
    private func updateTagPosition(_ tag: TagOnMap, position: CGPoint) {
        for lineIndex in timelineData.lines.indices {
            if timelineData.lines[lineIndex].id == tag.lineId {
                for stampIndex in timelineData.lines[lineIndex].stamps.indices {
                    if timelineData.lines[lineIndex].stamps[stampIndex].id == tag.stampId {
                        timelineData.lines[lineIndex].stamps[stampIndex].position = position
                        updateLocalTagPosition(tag, position: position)
                        timelineData.updateTimelines()
                        return
                    }
                }
            }
        }
    }
    
    private func updateLocalTagPosition(_ tag: TagOnMap, position: CGPoint) {
        let updatedTag = TagOnMap(
            id: tag.id,
            stampId: tag.stampId,
            lineId: tag.lineId,
            name: tag.name,
            colorHex: tag.colorHex,
            timeStart: tag.timeStart,
            timeFinish: tag.timeFinish,
            position: position,
            isActiveForMapView: tag.isActiveForMapView,
            number: tag.number
        )
        
        if let index = activeTags.firstIndex(where: { $0.id == tag.id }) {
            activeTags.remove(at: index)
            activeTags.insert(updatedTag, at: index)
            DispatchQueue.main.async {
                let tempTags = activeTags
                activeTags = []
                activeTags = tempTags
            }
        }
        
        if let index = inactiveTags.firstIndex(where: { $0.id == tag.id }) {
            inactiveTags.remove(at: index)
            inactiveTags.insert(updatedTag, at: index)
            
            DispatchQueue.main.async {
                let tempTags = inactiveTags
                inactiveTags = []
                inactiveTags = tempTags
            }
        }
        
        if selectedTagForMove?.id == tag.id {
            isMovingOnMap = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                selectedTagForMove = updatedTag
            }
        }
    }
    
    private func fieldPositionToScreenPosition(
        _ fieldPosition: CGPoint,
        fieldWidth: CGFloat,
        fieldHeight: CGFloat,
        imageWidth: CGFloat,
        imageHeight: CGFloat
    ) -> CGPoint {
        let fieldAspect = fieldWidth / fieldHeight
        let imageAspect = imageWidth / imageHeight
        
        var scaledWidth = imageWidth
        var scaledHeight = imageHeight
        var xOffset: CGFloat = 0
        var yOffset: CGFloat = 0
        
        if fieldAspect > imageAspect {
            scaledHeight = imageWidth / fieldAspect
            yOffset = (imageHeight - scaledHeight) / 2
        } else {
            scaledWidth = imageHeight * fieldAspect
            xOffset = (imageWidth - scaledWidth) / 2
        }
        
        let x = (fieldPosition.x / fieldWidth) * scaledWidth + xOffset
        let y = (fieldPosition.y / fieldHeight) * scaledHeight + yOffset
        
        return CGPoint(x: x, y: y)
    }
    
    private func screenPositionToFieldPosition(
        _ screenPosition: CGPoint,
        fieldWidth: CGFloat,
        fieldHeight: CGFloat,
        imageWidth: CGFloat,
        imageHeight: CGFloat
    ) -> CGPoint {
        let fieldAspect = fieldWidth / fieldHeight
        let imageAspect = imageWidth / imageHeight
        
        var scaledWidth = imageWidth
        var scaledHeight = imageHeight
        var xOffset: CGFloat = 0
        var yOffset: CGFloat = 0
        
        if fieldAspect > imageAspect {
            scaledHeight = imageWidth / fieldAspect
            yOffset = (imageHeight - scaledHeight) / 2
        } else {
            scaledWidth = imageHeight * fieldAspect
            xOffset = (imageWidth - scaledWidth) / 2
        }
        
        let adjustedX = screenPosition.x - xOffset
        let adjustedY = screenPosition.y - yOffset
        
        let x = (adjustedX / scaledWidth) * fieldWidth
        let y = (adjustedY / scaledHeight) * fieldHeight
        
        return CGPoint(x: x, y: y)
    }
    
}
