//
//  FieldMapVisualizationView.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 6/4/25.
//

import SwiftUI

struct FieldMapVisualizationView: View {
    let collection: CollectionBookmark
    let mode: VisualizationMode
    let stamps: [TimelineStamp]
    
    @State private var fieldImage: NSImage? = nil
    @State private var imageSize: CGSize = .zero
    @State private var selectedStamp: TimelineStamp? = nil
    @State private var hoveredStamp: TimelineStamp? = nil
    @State private var fieldDimensions: (width: Int, height: Int) = (0, 0)
    
    var body: some View {
        GeometryReader { geometry in
            VStack {
                HStack {
                    Text("Визуализация карты поля: \(collection.name)")
                        .font(.headline)
                    Spacer()
                    Text("Отображается \(stamps.count) тегов")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding()
                
                if let image = fieldImage {
                    ZStack {
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
                            .overlay(
                                ZStack {
                                    // Draw all stamps
                                    ForEach(stamps, id: \.id) { stamp in
                                        if let position = stamp.position {
                                            let screenPosition = fieldPositionToScreenPosition(
                                                position,
                                                fieldWidth: CGFloat(fieldDimensions.width),
                                                fieldHeight: CGFloat(fieldDimensions.height),
                                                imageWidth: imageSize.width,
                                                imageHeight: imageSize.height
                                            )
                                            
                                            ZStack {
                                                // Tag circle
                                                Circle()
                                                    .fill(Color(hex: stamp.colorHex))
                                                    .frame(width: 14, height: 14)
                                                
                                                // Border for hovered/selected tags
                                                if hoveredStamp?.id == stamp.id || selectedStamp?.id == stamp.id {
                                                    Circle()
                                                        .stroke(Color.white, lineWidth: 2)
                                                        .frame(width: 16, height: 16)
                                                }
                                            }
                                            .position(screenPosition)
                                            .onHover { isHovered in
                                                if isHovered {
                                                    hoveredStamp = stamp
                                                } else if hoveredStamp?.id == stamp.id {
                                                    hoveredStamp = nil
                                                }
                                            }
                                        }
                                    }
                                }
                            )
                    }
                    .padding()
                } else {
                    Text("Загрузка карты...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                
                if let selectedStamp = selectedStamp {
                    stampInfoView(selectedStamp)
                        .padding()
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                        .padding(.horizontal)
                }
            }
        }
        .frame(width: 1000, height: 500)
        .onAppear {
            loadFieldImageAndDimensions()
        }
    }
    
    private func stampInfoView(_ stamp: TimelineStamp) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Rectangle()
                    .fill(Color(hex: stamp.colorHex))
                    .frame(width: 14, height: 14)
                    .cornerRadius(2)
                
                Text(stamp.label)
                    .font(.headline)
                
                Spacer()
                
                Button(action: {
                    selectedStamp = nil
                }) {
                    Image(systemName: "xmark")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(BorderlessButtonStyle())
            }
            
            HStack {
                Text("Время:")
                    .foregroundColor(.secondary)
                Text("\(stamp.timeStart) - \(stamp.timeFinish)")
            }
            
            if let position = stamp.position {
                HStack {
                    Text("Позиция на поле:")
                        .foregroundColor(.secondary)
                    Text(String(format: "x: %.2f м, y: %.2f м", position.x, position.y))
                }
            }
            
            if !stamp.labels.isEmpty {
                Text("Лейблы:")
                    .foregroundColor(.secondary)
                
                let labels = stamp.labels.compactMap { labelID in
                    TagLibraryManager.shared.findLabelById(labelID)?.name
                }.joined(separator: ", ")
                
                Text(labels)
            }
        }
    }
    
    private func loadFieldImageAndDimensions() {
        let collectionManager = CustomCollectionManager()
        guard collectionManager.loadCollectionFromBookmarks(named: collection.name),
              let playField = collectionManager.playField,
              let imageBookmark = playField.imageBookmark else {
            return
        }
        
        fieldDimensions = (Int(playField.width), Int(playField.height))
        
        do {
            var isStale = false
            let url = try URL(resolvingBookmarkData: imageBookmark, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale)
            
            if url.startAccessingSecurityScopedResource() {
                fieldImage = NSImage(contentsOf: url)
                url.stopAccessingSecurityScopedResource()
            }
        } catch {
            print("Error loading field image: \(error)")
        }
    }
    
    private func fieldPositionToScreenPosition(_ fieldPosition: CGPoint, fieldWidth: CGFloat, fieldHeight: CGFloat, imageWidth: CGFloat, imageHeight: CGFloat) -> CGPoint {
        let normalizedX = fieldPosition.x / fieldWidth
        let normalizedY = fieldPosition.y / fieldHeight
        return CGPoint(
            x: normalizedX * imageWidth,
            y: normalizedY * imageHeight
        )
    }
}
