//
//  FreeTagsCanvasView.swift
//  Youchip-Stat
//
//  Отображение тегов по свободной раскладке коллекции.
//

import SwiftUI

struct FreeTagsCanvasView: View {
    
    let tags: [Tag]
    let onTagTap: (Tag) -> Void
    let activeIntervalTags: [TagLibraryView.ActiveIntervalTag]
    let hoveredTagID: String?
    let tagCounts: [String: Int]
    
    @State private var layout: TagFreeLayout?
    
    private var currentCollectionId: String? {
        if case .user(let name) = TagLibraryManager.shared.currentCollectionType {
            return CollectionsBookmarksManager.shared.loadCollections().first(where: { $0.name == name })?.id
        }
        return nil
    }
    
    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let effectiveLayout = layout ?? TagFreeLayoutStorage.makeDefaultLayout(for: tags)
            let fitScale = width / max(effectiveLayout.canvasWidth, 1)
            let scale = min(1.0, max(fitScale, 0.1))
            let canvasHeight = effectiveLayout.canvasHeight * scale
            
            ScrollView(.vertical) {
                ZStack {
                    Color.clear
                    
                    ForEach(effectiveLayout.items) { item in
                        if let tag = tags.first(where: { $0.id == item.tagId }) {
                            let viewSize = CGSize(width: item.size.width * scale, height: item.size.height * scale)
                            let viewCenter = CGPoint(x: item.center.x * scale, y: item.center.y * scale)
                            
                            FreeTagRuntimeItemView(
                                tag: tag,
                                item: item,
                                isActive: activeIntervalTags.contains(where: { $0.tag.id == tag.id }),
                                isHovered: hoveredTagID == tag.id,
                                tagCount: tagCounts[tag.id] ?? 0,
                                onTap: { onTagTap(tag) }
                            )
                            .frame(width: viewSize.width, height: viewSize.height)
                            .position(viewCenter)
                        }
                    }
                }
                .frame(width: width, height: canvasHeight)
            }
            .onAppear {
                loadLayoutIfNeeded()
            }
        }
        .frame(minHeight: 300)
    }
    
    private func loadLayoutIfNeeded() {
        guard let collectionId = currentCollectionId else { return }
        if let stored = TagFreeLayoutStorage.loadLayoutIfExists(collectionId: collectionId, tags: tags) {
            layout = stored
        } else {
            layout = TagFreeLayoutStorage.makeDefaultLayout(for: tags)
        }
    }
}

private struct FreeTagRuntimeItemView: View {
    let tag: Tag
    let item: TagFreeLayoutItem
    let isActive: Bool
    let isHovered: Bool
    let tagCount: Int
    let onTap: () -> Void
    
    var body: some View {
        let baseColor = Color(hex: tag.color).opacity(item.fillOpacity)
        let foreground: Color = {
            if let hex = item.textColor { return Color(hex: hex) }
            return Color(hex: tag.color).isDark ? Color.white : Color.black
        }()
        let strokeCol: Color = {
            if isActive { return Color.accentColor }
            if isHovered { return Color.accentColor.opacity(0.6) }
            if let hex = item.strokeColor { return Color(hex: hex) }
            return Color.black.opacity(0.25)
        }()
        let strokeStyle = StrokeStyle(
            lineWidth: isActive ? 2 : item.strokeWidth,
            dash: item.strokeDashed ? [4, 3] : []
        )
        let swiftWeight: Font.Weight = {
            if isActive { return .semibold }
            switch item.fontWeight {
            case .regular: return .regular
            case .medium: return .medium
            case .bold: return .bold
            }
        }()
        
        ZStack {
            TagFreeShapeView(shape: item.shape, cornerRadius: item.cornerRadius)
                .fill(baseColor)
                .overlay(
                    TagFreeShapeView(shape: item.shape, cornerRadius: item.cornerRadius)
                        .stroke(strokeCol, style: strokeStyle)
                )
            
            if item.showLabel {
                VStack(spacing: 2) {
                    Text(tag.name)
                        .font(.system(size: item.fontSize, weight: swiftWeight))
                        .foregroundColor(foreground)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.6)
                    
                    HStack(spacing: 4) {
                        if tagCount > 0 {
                            Text("\(tagCount)")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(foreground)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(Color.black.opacity(0.25)))
                        }
                        
                        if tag.isInterval == true {
                            Image(systemName: "timer")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(foreground.opacity(0.9))
                        }
                        
                        if tag.mapEnabled == true {
                            Image(systemName: "map")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(foreground.opacity(0.9))
                        }
                        
                        if let hotkey = tag.hotkey, !hotkey.isEmpty {
                            HStack(spacing: 3) {
                                Image(systemName: "keyboard")
                                    .font(.system(size: 9, weight: .medium))
                                Text(hotkey)
                                    .font(.system(size: 9, weight: .medium))
                            }
                            .padding(.horizontal, 3)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.black.opacity(0.25)))
                            .foregroundColor(foreground)
                        }
                    }
                }
                .padding(4)
            }
        }
        .shadow(
            color: item.shadowEnabled ? Color.black.opacity(item.shadowIntensity * 0.3) : Color.clear,
            radius: item.shadowEnabled ? (isHovered || isActive ? 6 : 3) : 0,
            x: 0,
            y: item.shadowEnabled ? 2 : 0
        )
        .rotationEffect(.degrees(item.rotation))
        .contentShape(Rectangle())
        .onTapGesture {
            onTap()
        }
    }
}
