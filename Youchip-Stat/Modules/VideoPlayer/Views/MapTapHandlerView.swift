//
//  MapTapHandlerView.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 6/19/25.
//

import SwiftUI

struct MapTapHandlerView: NSViewRepresentable {
    @Binding var isMovingOnMap: Bool
    @Binding var selectedTagForMove: TagOnMap?
    @Binding var showContextMenu: Bool
    let imageSize: CGSize
    let fieldDimensions: (width: Double, height: Double)
    let onTagPositionUpdate: (TagOnMap, CGPoint) -> Void
    
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        let clickGesture = NSClickGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleClick(_:)))
        view.addGestureRecognizer(clickGesture)
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject {
        var parent: MapTapHandlerView
        
        init(_ parent: MapTapHandlerView) {
            self.parent = parent
        }
        
        @objc func handleClick(_ gesture: NSClickGestureRecognizer) {
            if !parent.isMovingOnMap || parent.selectedTagForMove == nil {
                parent.showContextMenu = false
                return
            }
            
            guard let tag = parent.selectedTagForMove else { return }
            
            let location = gesture.location(in: gesture.view)
            
            if location.x >= 0 && location.x <= parent.imageSize.width &&
               location.y >= 0 && location.y <= parent.imageSize.height {
                
                let fixedLocation = CGPoint(
                    x: location.x,
                    y: parent.imageSize.height - location.y
                )
                
                let fieldPos = screenPositionToFieldPosition(
                    fixedLocation,
                    fieldWidth: CGFloat(parent.fieldDimensions.width),
                    fieldHeight: CGFloat(parent.fieldDimensions.height),
                    imageWidth: parent.imageSize.width,
                    imageHeight: parent.imageSize.height
                )
                
                parent.onTagPositionUpdate(tag, fieldPos)
                parent.isMovingOnMap = false
                parent.selectedTagForMove = nil
            }
        }
        
        func screenPositionToFieldPosition(
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
}
