//
//  FieldMapVisualizationWindowController.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 6/4/25.
//

import Cocoa
import SwiftUI

class FieldMapVisualizationWindowController: NSWindowController, ObservableObject {
    @Published var showVisualization = false
    @Published var selectedCollection: CollectionBookmark?
    @Published var selectedMode: VisualizationMode = .all
    @Published var selectedStamps: [TimelineStamp] = []

    private var windowContent: NSHostingController<AnyView>?

    init() {
        super.init(window: NSWindow())
        let content = FieldMapVisualizationPicker(
            onCancel: { [weak self] in self?.close() },
            onVisualize: { [weak self] collection, mode, stamps in
                self?.selectedCollection = collection
                self?.selectedMode = mode
                self?.selectedStamps = stamps
                self?.showVisualization = true
                self?.updateContent()
            }
        )
        let hosting = NSHostingController(rootView: AnyView(content.environmentObject(self)))
        self.window = NSWindow(contentViewController: hosting)
        self.windowContent = hosting
        self.window?.title = "Визуализация карты поля"
        self.window?.styleMask = [.titled, .closable, .miniaturizable]
        self.window?.setContentSize(NSSize(width: 1000, height: 500))
        self.window?.center()
    }


    required init?(coder: NSCoder) { fatalError() }

    func updateContent() {
        if showVisualization, let collection = selectedCollection {
            let view = FieldMapVisualizationView(
                collection: collection,
                mode: selectedMode,
                stamps: selectedStamps
            )
            windowContent?.rootView = AnyView(view)
        }
    }
}
