//
//  CreateCollectionTypeSheet.swift
//  Youchip-Stat
//
//  Окно выбора типа создаваемой коллекции (стандартная / связки клавиш).
//  Используется как из меню коллекций, так и из выпадающего списка коллекций
//  на экране библиотеки тегов.
//

import SwiftUI

struct CreateCollectionTypeSheet: View {

    @Binding var isPresented: Bool
    @State private var selectedDisplayMode: CollectionTagLibraryDisplayMode = .grouped

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(^String.Titles.collectionTypePickerTitle)
                .font(.title2)
                .fontWeight(.semibold)

            Text(^String.Titles.collectionTypePickerHint)
                .font(.subheadline)
                .foregroundColor(.secondary)

            Picker(^String.Titles.collectionTypePickerTitle, selection: $selectedDisplayMode) {
                Text(^String.Titles.collectionTypeStandard).tag(CollectionTagLibraryDisplayMode.grouped)
                Text(^String.Titles.collectionTypeKeyBindings).tag(CollectionTagLibraryDisplayMode.free)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            HStack {
                HStack(spacing: 8) {
                    Image(systemName: selectedDisplayMode == .free ? "keyboard" : "rectangle.grid.2x2")
                        .foregroundColor(selectedDisplayMode == .free ? .orange : .blue)
                    Text(selectedDisplayMode == .free
                         ? ^String.Titles.collectionTypeKeyBindingsDescription
                         : ^String.Titles.collectionTypeStandardDescription)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(12)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)

            Spacer()

            HStack {
                Spacer()
                Button(^String.Titles.cancelButtonTitle) {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)

                Button(^String.Titles.createNewCollection) {
                    let mode = selectedDisplayMode
                    isPresented = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        WindowsManager.shared.openCustomCollectionsWindow(initialDisplayMode: mode)
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 440, height: 280)
    }
}
