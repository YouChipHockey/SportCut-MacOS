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
    @State private var selectedTemplate: CollectionTemplate? = nil
    @State private var selectedTemplateLabel: String = ""

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

            templatePicker

            Spacer()

            HStack {
                Spacer()
                Button(^String.Titles.cancelButtonTitle) {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)

                Button(^String.Titles.createNewCollection) {
                    let mode = selectedDisplayMode
                    let template = selectedTemplate
                    isPresented = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        WindowsManager.shared.openCustomCollectionsWindow(initialDisplayMode: mode, template: template)
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 440, height: 340)
    }

    /// Выбор шаблона-основы: пусто / стандартная / пользовательская коллекция (копируется с новыми id).
    private var templatePicker: some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.on.doc").foregroundColor(.secondary)
            Text(^String.Titles.collectionsStartFromTemplate)
                .font(.subheadline)
            Spacer()
            Menu {
                Button(^String.Titles.collectionsTemplateEmpty) {
                    selectedTemplate = nil
                    selectedTemplateLabel = ^String.Titles.collectionsTemplateEmpty
                }
                let standard = TagLibraryManager.shared.standardCollections
                if !standard.isEmpty {
                    Section(^String.Titles.collectionsTemplateStandard) {
                        ForEach(standard, id: \.name) { std in
                            Button(std.name) {
                                selectedTemplate = .standard(name: std.name)
                                selectedTemplateLabel = std.name
                            }
                        }
                    }
                }
                let userCollections = CollectionsBookmarksManager.shared.loadCollections()
                if !userCollections.isEmpty {
                    Section(^String.Titles.collectionsTemplateUser) {
                        ForEach(userCollections, id: \.id) { info in
                            Button(info.name) {
                                selectedTemplate = .user(id: info.id, name: info.name)
                                selectedTemplateLabel = info.name
                            }
                        }
                    }
                }
            } label: {
                Text(selectedTemplateLabel.isEmpty ? ^String.Titles.collectionsTemplateEmpty : selectedTemplateLabel)
                    .lineLimit(1)
            }
            .fixedSize()
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
}
