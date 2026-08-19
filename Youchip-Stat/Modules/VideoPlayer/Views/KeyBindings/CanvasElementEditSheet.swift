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
    @State private var labelHotkey: String? = nil
    @State private var isCapturingLabelHotkey = false
    @State private var eventName = ""

    // Поля секундомера/таймера.
    @State private var clockName = ""
    @State private var clockCaption = ""
    @State private var clockMode: ClockMode = .stopwatch
    @State private var clockAppearance: ClockAppearance = .segments
    @State private var clockShowCentiseconds = true
    @State private var clockShowOnVideo = false
    @State private var clockHotkey: String? = nil
    @State private var isCapturingClockHotkey = false
    @State private var clockInitialMinutes = 10
    @State private var clockInitialSecs = 0
    @State private var clockZeroAction: ClockZeroAction = .stop
    @State private var clockFiresBindingsOnZero = false
    /// Тип при открытии — чтобы подгонять размер объекта только при смене типа.
    @State private var loadedClockAppearance: ClockAppearance = .segments

    private enum Tab: Hashable { case parameters, appearance }

    /// Редактируем счётчик — у него только собственные параметры, общей «внешности» нет.
    private var isClock: Bool { target.kind == .clock }

    /// Ввод целого времени руками (минуты/секунды), без отрицательных.
    private static let intFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .none
        f.allowsFloats = false
        f.minimum = 0
        f.maximum = 5999
        return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                // У счётчика вкладки «Внешний вид» нет: его оформление (вариант циферблата, сотые)
                // живёт в собственных параметрах, а общие настройки кнопки ему не подходят.
                if isClock {
                    Text(^String.Titles.clockCountersTitle)
                        .font(.headline)
                } else {
                    Picker("", selection: $tab) {
                        Text(^String.Titles.canvasEditTabParameters).tag(Tab.parameters)
                        Text(^String.Titles.canvasEditTabAppearance).tag(Tab.appearance)
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 360)
                }

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
                if !isClock {
                    appearanceTab
                        .opacity(tab == .appearance ? 1 : 0)
                        .allowsHitTesting(tab == .appearance)
                }
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
                labelHotkey = label.hotkey
            }
            if let event = collectionManager.timeEvents.first(where: { $0.id == target.elementId }) {
                eventName = event.name
            }
            if let clock = collectionManager.clocks.first(where: { $0.id == target.elementId }) {
                clockName = clock.name
                clockMode = clock.mode
                clockAppearance = clock.appearance
                clockShowCentiseconds = clock.showCentiseconds
                clockShowOnVideo = clock.showOnVideo
                clockHotkey = clock.hotkey
                clockInitialMinutes = Int(clock.initialSeconds) / 60
                clockInitialSecs = Int(clock.initialSeconds) % 60
                clockCaption = clock.caption
                clockZeroAction = clock.zeroAction
                clockFiresBindingsOnZero = clock.firesBindingsOnZero
                loadedClockAppearance = clock.appearance
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
        case .map:
            mapForm
        case .clock:
            clockForm
        }
    }

    private var clockForm: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    field(title: ^String.Titles.canvasEditName, text: $clockName)
                    field(title: ^String.Titles.clockCaptionTitle, text: $clockCaption)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(^String.Titles.clockModeTitle).font(.caption).foregroundColor(.secondary)
                        Picker("", selection: $clockMode) {
                            Text(^String.Titles.clockModeStopwatch).tag(ClockMode.stopwatch)
                            Text(^String.Titles.clockModeTimer).tag(ClockMode.timer)
                        }
                        .pickerStyle(.segmented)
                    }

                    if clockMode == .timer {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(^String.Titles.clockInitialValue).font(.caption).foregroundColor(.secondary)
                            HStack(spacing: 12) {
                                HStack(spacing: 4) {
                                    TextField("", value: $clockInitialMinutes, formatter: Self.intFormatter)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(width: 64)
                                        .multilineTextAlignment(.trailing)
                                    Text(^String.Titles.clockMinutesShort).foregroundColor(.secondary)
                                }
                                HStack(spacing: 4) {
                                    TextField("", value: $clockInitialSecs, formatter: Self.intFormatter)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(width: 64)
                                        .multilineTextAlignment(.trailing)
                                    Text(^String.Titles.clockSecondsShort).foregroundColor(.secondary)
                                }
                            }
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text(^String.Titles.clockZeroActionTitle).font(.caption).foregroundColor(.secondary)
                            Picker("", selection: $clockZeroAction) {
                                ForEach(ClockZeroAction.allCases, id: \.self) { action in
                                    Text(NSLocalizedString(action.localizationKey.capitalizeFirstLetter(), comment: "")).tag(action)
                                }
                            }
                            .pickerStyle(.menu)

                            Toggle(^String.Titles.clockFiresBindingsOnZero, isOn: $clockFiresBindingsOnZero)
                            Text(^String.Titles.clockFiresBindingsOnZeroHint)
                                .font(.caption2).foregroundColor(.secondary)
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text(^String.Titles.clockAppearanceTitle).font(.caption).foregroundColor(.secondary)
                        Picker("", selection: $clockAppearance) {
                            ForEach(ClockAppearance.allCases, id: \.self) { a in
                                Text(NSLocalizedString(a.localizationKey.capitalizeFirstLetter(), comment: "")).tag(a)
                            }
                        }
                        .pickerStyle(.menu)
                    }

                    Toggle(^String.Titles.clockShowCentiseconds, isOn: $clockShowCentiseconds)
                    Toggle(^String.Titles.clockShowOnVideo, isOn: $clockShowOnVideo)

                    hotkeyRow(hotkey: $clockHotkey, isCapturing: $isCapturingClockHotkey)
                }
                .padding(24)
            }
            Divider()
            saveCancelBar {
                let total = Double(clockInitialMinutes * 60 + clockInitialSecs)
                let updated = ClockEntity(
                    id: target.elementId,
                    name: clockName.isEmpty ? (clockMode == .timer ? ^String.Titles.clockModeTimer : ^String.Titles.clockModeStopwatch) : clockName,
                    mode: clockMode,
                    initialSeconds: total,
                    appearance: clockAppearance,
                    showCentiseconds: clockShowCentiseconds,
                    showOnVideo: clockShowOnVideo,
                    zeroAction: clockZeroAction,
                    firesBindingsOnZero: clockFiresBindingsOnZero,
                    caption: clockCaption,
                    hotkey: normalizedHotkey(clockHotkey)
                )
                collectionManager.updateClock(updated)
                _ = collectionManager.saveCollectionToFiles()
                ClockRuntimeManager.shared.register(collectionManager.clocks)
                HotKeyManager.shared.registerCanvasElementHotkeys(
                    labels: collectionManager.labels, clocks: collectionManager.clocks
                )
                resizeClockItem(to: clockAppearance, showCentis: clockShowCentiseconds)
            }
        }
    }

    /// Подгоняет размер объекта-счётчика на холсте под выбранный тип (только при смене типа,
    /// чтобы не затирать ручной ресайз). Segments — широкий, analog/ring — квадрат, text — средний.
    private func resizeClockItem(to appearance: ClockAppearance, showCentis: Bool) {
        guard appearance != loadedClockAppearance,
              let idx = layout.items.firstIndex(where: { $0.elementId == target.elementId && $0.kind == .clock }) else { return }
        let size: CGSize
        switch appearance {
        case .segments: size = CGSize(width: showCentis ? 240 : 190, height: 64)
        case .text:     size = CGSize(width: showCentis ? 170 : 140, height: 52)
        case .analog:   size = CGSize(width: 96, height: 96)
        case .ring:     size = CGSize(width: 96, height: 96)
        }
        layout.items[idx].size = size
        loadedClockAppearance = appearance
    }

    private var mapForm: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(collectionManager.playFields.first(where: { $0.id == target.elementId })?.name ?? target.elementId)
                        .font(.headline)
                    Text(^String.Titles.keyBindingsMapZoneHint)
                        .font(.caption).foregroundColor(.secondary)
                }
                .padding(24)
            }
            Divider()
            saveCancelBar { }
        }
    }

    private var labelForm: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    field(title: ^String.Titles.canvasEditName, text: $labelName)
                    field(title: ^String.Titles.description, text: $labelDescription)
                    hotkeyRow(hotkey: $labelHotkey, isCapturing: $isCapturingLabelHotkey)
                }
                .padding(24)
            }
            Divider()
            saveCancelBar {
                collectionManager.updateLabel(
                    id: target.elementId,
                    name: labelName,
                    description: labelDescription,
                    hotkey: normalizedHotkey(labelHotkey)
                )
                _ = collectionManager.saveCollectionToFiles()
                HotKeyManager.shared.registerCanvasElementHotkeys(
                    labels: collectionManager.labels, clocks: collectionManager.clocks
                )
            }
        }
    }

    /// Пустую строку хоткея нормализуем в nil, чтобы не хранить «пустой» хоткей.
    private func normalizedHotkey(_ value: String?) -> String? {
        guard let v = value, !v.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return v
    }

    /// Захват горячей клавиши — тот же UI, что у тега (см. CollectionTagEditorSheets.hotkeySection).
    /// Хоткей = просто способ нажатия элемента в разметке; вся логика после нажатия не меняется.
    private func hotkeyRow(hotkey: Binding<String?>, isCapturing: Binding<Bool>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(^String.Titles.hotkeys).font(.caption).foregroundColor(.secondary)
            HStack(spacing: 8) {
                ZStack {
                    Button(action: { isCapturing.wrappedValue = true }) {
                        HStack {
                            Image(systemName: "keyboard")
                            Text(hotkey.wrappedValue ?? ^String.Titles.assign)
                        }
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color(NSColor.controlBackgroundColor)))
                    }
                    .buttonStyle(.plain)
                    if isCapturing.wrappedValue {
                        KeyCaptureView(keyString: hotkey, isCapturing: isCapturing)
                            .allowsHitTesting(false)
                    }
                }
                if let hk = hotkey.wrappedValue, !hk.isEmpty, !isCapturing.wrappedValue {
                    Button(action: { hotkey.wrappedValue = nil }) {
                        Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(^String.Titles.reset)
                }
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
