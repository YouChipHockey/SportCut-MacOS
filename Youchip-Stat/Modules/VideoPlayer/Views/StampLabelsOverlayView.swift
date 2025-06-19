//
//  StampLabelsOverlayView.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 6/19/25.
//

import SwiftUI
import AVKit
import Cocoa
import AVFoundation
import UniformTypeIdentifiers

struct StampLabelsOverlayView: View {
    
    let stamp: TimelineStamp
    let maxWidth: CGFloat
    let isResizing: Bool
    @ObservedObject var tagLibrary = TagLibraryManager.shared
    
    @State private var displayedLabels: [Label] = []
    @State private var displayedTimeEvents: [TimeEvent] = []
    @State private var fontSize: CGFloat = 12
    
    init(stamp: TimelineStamp, maxWidth: CGFloat, isResizing: Bool = false) {
        self.stamp = stamp
        self.maxWidth = maxWidth
        self.isResizing = isResizing
    }
    
    var body: some View {
        GeometryReader { proxy in
            if !isResizing {
                let finalWidth = proxy.size.width
                let labelsWidth = finalWidth * 0.5
                let eventsWidth = finalWidth * 0.5
                
                HStack(spacing: 2) {
                    HStack(spacing: 4) {
                        ForEach(displayedLabels, id: \.id) { label in
                            LabelChip(label: label, baseColor: stamp.color, fontSize: fontSize)
                        }
                    }
                    .frame(width: labelsWidth, alignment: .leading)
                    HStack(spacing: 4) {
                        ForEach(displayedTimeEvents, id: \.id) { event in
                            TimeEventChip(event: event, fontSize: fontSize)
                        }
                    }
                    .frame(width: eventsWidth, alignment: .trailing)
                }
                .frame(height: proxy.size.height, alignment: .center)
            }
        }
        .onAppear {
            updateDisplayedItems(finalWidth: maxWidth)
        }
        .onChange(of: maxWidth) { newValue in
            updateDisplayedItems(finalWidth: newValue)
        }
        .onChange(of: stamp.labels) { _ in
            updateDisplayedItems(finalWidth: maxWidth)
        }
        .onChange(of: stamp.timeEvents) { _ in
            updateDisplayedItems(finalWidth: maxWidth)
        }
    }
    
    private func updateDisplayedItems(finalWidth: CGFloat) {
        let labelsWidth = finalWidth * 0.5
        let eventsWidth = finalWidth * 0.5
        updateDisplayedLabels(availableWidth: labelsWidth)
        updateDisplayedTimeEvents(availableWidth: eventsWidth)
    }
    
    private func updateDisplayedLabels(availableWidth: CGFloat) {
        let stampLabels = stamp.labels.compactMap { labelID in
            tagLibrary.findLabelById(labelID)
        }
        
        if stampLabels.isEmpty {
            displayedLabels = []
            return
        }
        
        var testFont: CGFloat = 12
        let totalWidthOfAll = stampLabels.reduce(0) { partialResult, label in
            let textWidth = label.name.size(withSystemFontOfSize: testFont).width + 20
            return partialResult + textWidth + 4
        }
        
        if totalWidthOfAll <= availableWidth {
            displayedLabels = stampLabels
            fontSize = testFont
            return
        }
        
        if let firstLabel = stampLabels.first {
            let firstLabelWidth = firstLabel.name.size(withSystemFontOfSize: testFont).width + 20
            
            if firstLabelWidth > availableWidth {
                testFont = 10
                let newFirstWidth = firstLabel.name.size(withSystemFontOfSize: testFont).width + 20
                
                if newFirstWidth > availableWidth {
                    displayedLabels = []
                    return
                } else {
                    displayedLabels = [firstLabel]
                    fontSize = testFont
                    return
                }
            }
        }
        
        var listToShow: [Label] = []
        var currentWidth: CGFloat = 0
        
        for lb in stampLabels {
            let neededWidth = lb.name.size(withSystemFontOfSize: testFont).width + 20 + 4
            if currentWidth + neededWidth <= availableWidth {
                listToShow.append(lb)
                currentWidth += neededWidth
            } else {
                break
            }
        }
        
        displayedLabels = listToShow
        fontSize = testFont
    }
    
    private func updateDisplayedTimeEvents(availableWidth: CGFloat) {
        let events = stamp.timeEvents.compactMap { eventID in
            tagLibrary.allTimeEvents.first(where: { $0.id == eventID })
        }
        if events.isEmpty {
            displayedTimeEvents = []
            return
        }
        
        var testFont: CGFloat = 12
        let totalWidthOfAll = events.reduce(0) { partialResult, event in
            let textWidth = event.name.size(withSystemFontOfSize: testFont).width + 20
            return partialResult + textWidth + 4
        }
        
        if totalWidthOfAll <= availableWidth {
            displayedTimeEvents = events
            return
        }
        
        if let firstEvent = events.first {
            let firstEventWidth = firstEvent.name.size(withSystemFontOfSize: testFont).width + 20
            
            if firstEventWidth > availableWidth {
                testFont = 10
                let newFirstWidth = firstEvent.name.size(withSystemFontOfSize: testFont).width + 20
                
                if newFirstWidth > availableWidth {
                    displayedTimeEvents = []
                    return
                } else {
                    displayedTimeEvents = [firstEvent]
                    fontSize = testFont
                    return
                }
            }
        }
        
        var listToShow: [TimeEvent] = []
        var currentWidth: CGFloat = 0
        
        for event in events {
            let neededWidth = event.name.size(withSystemFontOfSize: testFont).width + 20 + 4
            if currentWidth + neededWidth <= availableWidth {
                listToShow.append(event)
                currentWidth += neededWidth
            } else {
                break
            }
        }
        
        displayedTimeEvents = listToShow
    }
    
}
