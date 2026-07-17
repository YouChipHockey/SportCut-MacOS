//
//  CanvasElementEditSheet.swift
//  Youchip-Stat
//
//  Окно редактирования элемента раскладки (по двойному клику по кнопке на холсте).
//  Две вкладки:
//   - «Параметры» — параметры самого тега/лейбла/события (как в левом меню навигации);
//   - «Внешний вид» — настройки раскладки элемента (как в правой панели редактора).
//

import SwiftUI

struct CanvasElementEditSheet: View {

    @ObservedObject var collectionManager: CustomCollectionManager
    @Binding var layout: TagFreeLayout
    let target: PendingCanvasEdit
    var onDismiss: () -> Void

    @Environment(\.presentationMode) private var presentationMode
    @StateObject private var layoutSession = TagFreeLayoutEditorSession()
    @State private var tab: Tab = .parameters

    // Локальные поля для лейбла/события (у тега — свой полноценный редактор).
    @State private var labelName = ""
    @State private var labelDescription = ""
    @State private var eventName = ""

    private enum Tab: Hashable { case parameters, appearance }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Picker("", selection: $tab) {
                    Text(^String.Titles.canvasEditTabParameters).tag(Tab.parameters)
                    Text(^String.Titles.canvasEditTabAppearance).tag(Tab.appearance)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 360)

                Spacer()

                Button(action: close) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help(^String.Titles.cancelButtonTitle)
            }
            .padding(12)

            Divider()

            // Обе вкладки живут одновременно, чтобы не терять несохранённые правки при переключении.
            ZStack {
                parametersTab
                    .opacity(tab == .parameters ? 1 : 0)
                    .allowsHitTesting(tab == .parameters)
                appearanceTab
                    .opacity(tab == .appearance ? 1 : 0)
                    .allowsHitTesting(tab == .appearance)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 640, height: 780)
        .onAppear {
            layoutSession.editorMode = .layout
            layoutSession.selectedItemId = target.id
            if let label = collectionManager.labels.first(where: { $0.id == target.elementId }) {
                labelName = label.name
                labelDescription = label.description
            }
            if let event = collectionManager.timeEvents.first(where: { $0.id == target.elementId }) {
                eventName = event.name
            }
        }
    }

    // MARK: - Параметры (левое меню)

    @ViewBuilder
    private var parametersTab: some View {
        switch target.kind {
        case .tag:
            if let tag = collectionManager.tags.first(where: { $0.id == target.elementId }) {
                TagEditSheetView(collectionManager: collectionManager, tag: tag, onDismiss: onDismiss)
            } else {
                missingElement
            }
        case .label:
            labelForm
        case .timeEvent:
            eventForm
        }
    }

    private var labelForm: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    field(title: ^String.Titles.canvasEditName, text: $labelName)
                    field(title: ^String.Titles.description, text: $labelDescription)
                }
                .padding(24)
            }
            Divider()
            saveCancelBar {
                collectionManager.updateLabel(id: target.elementId, name: labelName, description: labelDescription)
            }
        }
    }

    private var eventForm: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    field(title: ^String.Titles.canvasEditName, text: $eventName)
                }
                .padding(24)
            }
            Divider()
            saveCancelBar {
                collectionManager.updateTimeEvent(id: target.elementId, newName: eventName)
            }
        }
    }

    private func field(title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundColor(.secondary)
            TextField("", text: text)
                .textFieldStyle(.roundedBorder)
        }
    }

    private func close() {
        onDismiss()
        presentationMode.wrappedValue.dismiss()
    }

    private func saveCancelBar(_ save: @escaping () -> Void) -> some View {
        HStack {
            Button(^String.Titles.collectionsButtonCancel) {
                onDismiss()
                presentationMode.wrappedValue.dismiss()
            }
            Spacer()
            Button(^String.Titles.collectionsButtonSaveChanges) {
                save()
                onDismiss()
                presentationMode.wrappedValue.dismiss()
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
        }
        .padding(20)
    }

    private var missingElement: some View {
        VStack {
            Spacer()
            Text(^String.Titles.freeLayoutSelectElement)
                .foregroundColor(.secondary)
            Spacer()
        }
    }

    // MARK: - Внешний вид (правое меню)

    private var appearanceTab: some View {
        TagFreeLayoutEditorContent(
            session: layoutSession,
            layout: $layout,
            tags: collectionManager.tags,
            labels: collectionManager.labels,
            timeEvents: collectionManager.timeEvents,
            pane: .settings,
            showsModePicker: false,
            settingsPaneFillsWidth: true
        )
    }
}
