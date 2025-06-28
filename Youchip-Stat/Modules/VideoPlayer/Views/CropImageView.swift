//
//  CropImageView.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 6/3/25.
//

import SwiftUI
import AppKit

struct CropImageView: View {
    @Environment(\.presentationMode) var presentationMode
    let imageURL: URL
    let onCrop: (NSImage) -> Void
    
    @State private var image: NSImage?
    @State private var cropRect: CGRect = .zero
    @State private var viewSize: CGSize = .zero
    @State private var isDragging: Bool = false
    @State private var dragStartPoint: CGPoint = .zero
    @State private var hasSelection: Bool = false
    @State private var imageFrame: CGRect = .zero
    
    init(imageURL: URL, onCrop: @escaping (NSImage) -> Void) {
        self.imageURL = imageURL
        self.onCrop = onCrop
        _image = State(initialValue: NSImage(contentsOf: imageURL))
    }
    
    var body: some View {
        VStack {
            Text(^String.Titles.selectFieldMapArea)
                .font(.headline)
                .padding(.top)
            
            GeometryReader { geometry in
                ZStack {
                    Color.clear
                        .onAppear {
                            viewSize = geometry.size
                        }
                    
                    if let image = image {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .background(GeometryReader { imageGeometry in
                                Color.clear
                                    .onAppear {
                                        imageFrame = CGRect(origin: .zero, size: imageGeometry.size)
                                    }
                            })
                            .background(Color.black.opacity(0.2))
                    }
                    
                    if hasSelection {
                        ZStack {
                            ZStack {
                                Rectangle()
                                    .fill(Color.black.opacity(0.5))
                                    .frame(width: viewSize.width, height: cropRect.minY)
                                    .position(x: viewSize.width/2, y: cropRect.minY/2)
                                
                                Rectangle()
                                    .fill(Color.black.opacity(0.5))
                                    .frame(width: viewSize.width, height: viewSize.height - cropRect.maxY)
                                    .position(x: viewSize.width/2, y: (viewSize.height + cropRect.maxY)/2)
                                
                                Rectangle()
                                    .fill(Color.black.opacity(0.5))
                                    .frame(width: cropRect.minX, height: cropRect.height)
                                    .position(x: cropRect.minX/2, y: cropRect.midY)
                                
                                Rectangle()
                                    .fill(Color.black.opacity(0.5))
                                    .frame(width: viewSize.width - cropRect.maxX, height: cropRect.height)
                                    .position(x: (viewSize.width + cropRect.maxX)/2, y: cropRect.midY)
                            }
                            
                            Rectangle()
                                .stroke(Color.red, lineWidth: 2)
                                .frame(width: cropRect.width, height: cropRect.height)
                                .position(x: cropRect.midX, y: cropRect.midY)
                        }
                        .allowsHitTesting(false)
                    }
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 1)
                        .onChanged { value in
                            if !isDragging {
                                isDragging = true
                                dragStartPoint = value.startLocation
                                cropRect = CGRect(origin: dragStartPoint, size: .zero)
                            }
                            
                            let currentPoint = value.location
                            
                            let minX = min(dragStartPoint.x, currentPoint.x)
                            let minY = min(dragStartPoint.y, currentPoint.y)
                            let width = abs(currentPoint.x - dragStartPoint.x)
                            let height = abs(currentPoint.y - dragStartPoint.y)
                            
                            cropRect = CGRect(x: minX, y: minY, width: width, height: height)
                            
                            let viewBounds = CGRect(origin: .zero, size: viewSize)
                            cropRect = cropRect.intersection(viewBounds)
                            
                            hasSelection = cropRect.width > 10 && cropRect.height > 10
                        }
                        .onEnded { _ in
                            isDragging = false
                        }
                )
                .onTapGesture {
                    hasSelection = false
                    cropRect = .zero
                }
            }
            .clipped()
            .padding()
            
            HStack {
                Button(^String.Titles.collectionsButtonCancel) {
                    presentationMode.wrappedValue.dismiss()
                }
                
                Spacer()
                
                Button(^String.Titles.rrepeat) {
                    hasSelection = false
                    cropRect = .zero
                }
                .disabled(!hasSelection)
                
                Spacer()
                
                Button(^String.Titles.apply) {
                    if let image = image, hasSelection {
                        let croppedImage = cropImage(image: image)
                        onCrop(croppedImage)
                        presentationMode.wrappedValue.dismiss()
                    }
                }
                .keyboardShortcut(.return)
                .buttonStyle(BorderedButtonStyle())
                .disabled(!hasSelection)
            }
            .padding()
        }
        .frame(width: 700, height: 500)
    }
    
    private func cropImage(image: NSImage) -> NSImage {
        let imageSize = image.size
        let viewRatio = viewSize.width / viewSize.height
        let imageRatio = imageSize.width / imageSize.height
        
        let displayedImageSize: CGSize
        let displayedImageOrigin: CGPoint
        
        if imageRatio > viewRatio {
            displayedImageSize = CGSize(
                width: viewSize.width,
                height: viewSize.width / imageRatio
            )
            displayedImageOrigin = CGPoint(
                x: 0,
                y: (viewSize.height - displayedImageSize.height) / 2
            )
        } else {
            displayedImageSize = CGSize(
                width: viewSize.height * imageRatio,
                height: viewSize.height
            )
            displayedImageOrigin = CGPoint(
                x: (viewSize.width - displayedImageSize.width) / 2,
                y: 0
            )
        }
        
        let adjustedCropRect = CGRect(
            x: (cropRect.minX - displayedImageOrigin.x) / displayedImageSize.width * imageSize.width,
            y: (cropRect.minY - displayedImageOrigin.y) / displayedImageSize.height * imageSize.height,
            width: cropRect.width / displayedImageSize.width * imageSize.width,
            height: cropRect.height / displayedImageSize.height * imageSize.height
        )
        
        let resultImage = NSImage(size: NSSize(width: adjustedCropRect.width, height: adjustedCropRect.height))
        resultImage.lockFocus()
        
        NSGraphicsContext.current?.imageInterpolation = .high
        
        let sourceRect = CGRect(
            x: adjustedCropRect.origin.x,
            y: imageSize.height - adjustedCropRect.maxY,
            width: adjustedCropRect.width,
            height: adjustedCropRect.height
        )
        
        image.draw(in: CGRect(origin: .zero, size: resultImage.size),
                  from: sourceRect,
                  operation: .copy,
                  fraction: 1.0)
        
        resultImage.unlockFocus()
        
        return resizeImageToHeight(image: resultImage, height: 300)
    }
    
    private func resizeImageToHeight(image: NSImage, height: CGFloat) -> NSImage {
        let aspectRatio = image.size.width / image.size.height
        let newWidth = height * aspectRatio
        let targetSize = NSSize(width: newWidth, height: height)
        
        let resizedImage = NSImage(size: targetSize)
        resizedImage.lockFocus()
        
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: NSRect(origin: .zero, size: targetSize),
                   from: NSRect(origin: .zero, size: image.size),
                   operation: .copy, fraction: 1.0)
        
        resizedImage.unlockFocus()
        return resizedImage
    }
}
