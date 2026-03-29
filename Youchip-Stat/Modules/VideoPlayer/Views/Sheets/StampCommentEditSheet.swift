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
            Text("Комментарий")
                .font(.headline)

            TextEditor(text: $commentText)
                .font(.system(size: 13))
                .frame(minHeight: 100)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                )

            HStack {
                Button("Отмена") {
                    presentationMode.wrappedValue.dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Сохранить") {
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
