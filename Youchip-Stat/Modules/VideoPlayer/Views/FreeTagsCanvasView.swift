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
            let scale = max(width / max(effectiveLayout.canvasWidth, 1), 0.1)
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
        let baseColor = Color(hex: tag.color)
        let foreground = baseColor.isDark ? Color.white : Color.black
        
        ZStack {
            TagFreeShapeView(shape: item.shape)
                .fill(baseColor)
                .shadow(
                    color: Color.black.opacity(0.15),
                    radius: isHovered || isActive ? 6 : 3,
                    x: 0,
                    y: 2
                )
                .overlay(
                    TagFreeShapeView(shape: item.shape)
                        .stroke(
                            isActive ? Color.accentColor :
                                (isHovered ? Color.accentColor.opacity(0.6) : Color.black.opacity(0.25)),
                            lineWidth: isActive ? 2 : 1
                        )
                )
            
            VStack(spacing: 2) {
                Text(tag.name)
                    .font(.system(size: 12, weight: isActive ? .semibold : .medium))
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
                            .background(
                                Capsule()
                                    .fill(Color.black.opacity(0.25))
                            )
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
                        .background(
                            Capsule()
                                .fill(Color.black.opacity(0.25))
                        )
                        .foregroundColor(foreground)
                    }
                }
            }
            .padding(4)
        }
        .rotationEffect(.degrees(item.rotation))
        .contentShape(Rectangle())
        .onTapGesture {
            onTap()
        }
    }
}
