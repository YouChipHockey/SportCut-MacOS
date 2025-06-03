//
//  SharingPicker.swift
//  Youchip-Stat
//
//  Created by Сергей Бекезин on 5/27/25.
//

import SwiftUI
import TinyConstraints

struct SharingPicker: NSViewRepresentable {

    class Coordinator: NSObject, NSSharingServicePickerDelegate {

        var parent: SharingPicker

        init(_ parent: SharingPicker) {
            self.parent = parent
        }

        func sharingServicePicker(_ sharingServicePicker: NSSharingServicePicker, didChoose service: NSSharingService?) {
            parent.closeExport?()
        }

    }

    let show: Binding<Bool>
    let items: [Any]
    let closeExport: (() -> Void)?

    init(show: Binding<Bool>, items: [Any], closeExport: (() -> Void)? = nil) {
        self.show = show
        self.items = items
        self.closeExport = closeExport
    }

    func makeCoordinator() -> Coordinator {
        return Coordinator(self)
    }

    func makeNSView(context: Context) -> NSView {
        return NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if show.wrappedValue {
            DispatchQueue.main.async {
                let picker = NSSharingServicePicker(items: items)
                picker.delegate = context.coordinator
                picker.show(
                    relativeTo: nsView.bounds,
                    of: nsView,
                    preferredEdge: .minY
                )
                show.wrappedValue = false
            }
        }
    }

}
