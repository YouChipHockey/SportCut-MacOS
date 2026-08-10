//
//  StampCommentEditSheet.swift
//  Youchip-Stat
//

import SwiftUI

struct StampCommentEditSheet: View {

    @Environment(\.presentationMode) var presentationMode
    @State private var commentText: String
    @State private var eventMonitor: Any? = nil
    let onSave: (String) -> Void

    init(stamp: TimelineStamp, onSave: @escaping (String) -> Void) {
        _commentText = State(initialValue: stamp.comment ?? "")
        self.onSave = onSave
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(^String.Titles.stampCommentTitle)
                .font(.headline)

            TextEditor(text: $commentText)
                .font(.system(size: 13))
                .frame(minHeight: 100)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                )

            HStack {
                Button(^String.Titles.cancelButtonTitle) {
                    presentationMode.wrappedValue.dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button(^String.Titles.saveButtonTitle) {
                    onSave(commentText)
                    presentationMode.wrappedValue.dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 360)
        .onAppear {
            HotKeyManager.shared.isEnabled = false
            if let existing = eventMonitor { NSEvent.removeMonitor(existing); eventMonitor = nil }
            eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                guard event.keyCode == 36 else { return event } // 36 = Return
                if event.modifierFlags.contains(.shift) {
                    return event // Shift+Return → newline in TextEditor
                }
                onSave(commentText)
                presentationMode.wrappedValue.dismiss()
                return nil
            }
        }
        .onDisappear {
            HotKeyManager.shared.isEnabled = true
            if let monitor = eventMonitor {
                NSEvent.removeMonitor(monitor)
                eventMonitor = nil
            }
        }
    }
}
