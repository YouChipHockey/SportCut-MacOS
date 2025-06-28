//
//  FieldMapSelectionView.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 6/19/25.
//

import SwiftUI
import AVKit
import Cocoa
import AVFoundation
import UniformTypeIdentifiers

struct FieldMapSelectionView: View {
    
    let tag: Tag
    let imageBookmark: Data
    let onSave: (CGPoint) -> Void
    
    @State private var selectedCoordinate: CGPoint? = nil
    @State private var fieldImage: NSImage? = nil
    @State private var imageSize: CGSize = .zero
    @State private var originalImageSize: CGSize = .zero
    @State private var normalizedCoordinate: CGPoint? = nil
    @Environment(\.presentationMode) private var presentationMode
    
    var body: some View {
        VStack(spacing: 16) {
            if let image = fieldImage {
                ZStack {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .background(
                            GeometryReader { geo in
                                Color.clear.onAppear {
                                    originalImageSize = image.size
                                    imageSize = geo.size
                                }
                                .onChange(of: geo.size) { newSize in
                                    imageSize = newSize
                                    updateSelectedCoordinateForNewSize()
                                }
                            }
                        )
                        .overlay(
                            ZStack {
                                if let coordinate = selectedCoordinate {
                                    Circle()
                                        .fill(Color(hex: tag.color))
                                        .frame(width: 20, height: 20)
                                        .position(coordinate)
                                    
                                    Circle()
                                        .stroke(Color.white, lineWidth: 2)
                                        .frame(width: 20, height: 20)
                                        .position(coordinate)
                                }
                            }
                        )
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onEnded { value in
                                    if value.location.x >= 0 && value.location.x <= imageSize.width &&
                                        value.location.y >= 0 && value.location.y <= imageSize.height {
                                        selectedCoordinate = value.location
                                        normalizedCoordinate = CGPoint(
                                            x: value.location.x / imageSize.width,
                                            y: value.location.y / imageSize.height
                                        )
                                    }
                                }
                        )
                }
                .padding()
                .background(Color.black.opacity(0.05))
                .cornerRadius(8)
            } else {
                Text(^String.Titles.failedToLoadFieldMap)
                    .foregroundColor(.red)
                    .padding()
            }
            
            HStack {
                Button(^String.Titles.collectionsButtonCancel) {
                    NSApp.keyWindow?.close()
                }
                .keyboardShortcut(.escape)
                
                Spacer()
                
                Button(^String.Titles.saveButtonTitle) {
                    if let normalized = normalizedCoordinate {
                        onSave(normalized)
                    }
                    NSApp.keyWindow?.close()
                }
                .keyboardShortcut(.return)
                .disabled(selectedCoordinate == nil)
            }
            .padding()
        }
        .frame(minWidth: 500, minHeight: 400)
        .onAppear {
            loadFieldImage()
        }
    }
    
    private func updateSelectedCoordinateForNewSize() {
        guard let normalized = normalizedCoordinate else { return }
        selectedCoordinate = CGPoint(
            x: normalized.x * imageSize.width,
            y: normalized.y * imageSize.height
        )
    }
    
    private func loadFieldImage() {
        do {
            var isStale = false
            let url = try URL(resolvingBookmarkData: imageBookmark, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale)
            
            if url.startAccessingSecurityScopedResource() {
                if let image = NSImage(contentsOf: url) {
                    fieldImage = image
                    originalImageSize = image.size
                }
                url.stopAccessingSecurityScopedResource()
            }
        } catch {
            print("Error loading field image: \(error)")
        }
    }
    
}
