//
//  ProjectMergeView.swift
//  Youchip-Stat
//
//  Окно объединения нескольких проектов в один.
//

import SwiftUI
import UniformTypeIdentifiers

struct ProjectMergeView: View {

    @EnvironmentObject private var viewModel: VideosViewModel
    @ObservedObject private var mergeManager = ProjectMergeManager.shared

    /// Проекты в порядке выбора; порядок можно поменять прямо здесь.
    @State private var sources: [ProjectMergeSource]
    @State private var projectName: String
    /// Имена одноимённых дорожек, отмеченные для объединения в одну (по умолчанию — все).
    @State private var mergedNameSelection: Set<String>
    @State private var errorMessage: String?

    private let onFinished: (FilesFile) -> Void
    private let onCancel: () -> Void

    init(
        sources: [ProjectMergeSource],
        onFinished: @escaping (FilesFile) -> Void,
        onCancel: @escaping () -> Void
    ) {
        _sources = State(initialValue: sources)
        _projectName = State(initialValue: Self.defaultName(for: sources))
        _mergedNameSelection = State(initialValue: Set(Self.computeDuplicateLineNames(in: sources)))
        self.onFinished = onFinished
        self.onCancel = onCancel
    }

    /// Названия дорожек (кроме дорожки рисунков), встречающиеся более одного раза среди выбранных проектов.
    private static func computeDuplicateLineNames(in sources: [ProjectMergeSource]) -> [String] {
        var counts: [String: Int] = [:]
        for source in sources {
            for line in source.file.timelines where !line.isDrawingsTimeline {
                counts[line.name, default: 0] += 1
            }
        }
        return counts.filter { $0.value >= 2 }.keys.sorted()
    }

    private var duplicateLineNames: [String] { Self.computeDuplicateLineNames(in: sources) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            Divider()

            if mergeManager.isMerging {
                progressSection
            } else {
                formSection
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 12))
                    .foregroundColor(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }

            Divider()

            footer
        }
        .padding(20)
        .frame(width: 520)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(^String.Titles.mergeProjectsTitle)
                .font(.system(size: 16, weight: .semibold))
            Text(^String.Titles.mergeProjectsSubtitle)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var formSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(^String.Titles.mergeProjectsNameLabel)
                    .font(.system(size: 12, weight: .medium))
                TextField("", text: $projectName)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(^String.Titles.mergeProjectsOrderLabel)
                    .font(.system(size: 12, weight: .medium))

                VStack(spacing: 0) {
                    ForEach(Array(sources.enumerated()), id: \.element.id) { index, source in
                        orderRow(index: index, source: source)
                        if index < sources.count - 1 {
                            Divider()
                        }
                    }
                }
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                )
            }

            if !duplicateLineNames.isEmpty {
                sameNamedLinesSection
            }
        }
    }

    /// Показывается только когда есть одноимённые дорожки: пользователь отмечает, какие объединить.
    private var sameNamedLinesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(^String.Titles.mergeProjectsMergeLinesTitle)
                .font(.system(size: 12, weight: .medium))
            Text(^String.Titles.mergeProjectsMergeLinesHint)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(duplicateLineNames, id: \.self) { name in
                    Toggle(isOn: Binding(
                        get: { mergedNameSelection.contains(name) },
                        set: { isOn in
                            if isOn { mergedNameSelection.insert(name) }
                            else { mergedNameSelection.remove(name) }
                        }
                    )) {
                        Text(name)
                            .font(.system(size: 12))
                            .lineLimit(1)
                    }
                    .toggleStyle(CheckboxToggleStyle())
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(NSColor.separatorColor), lineWidth: 1)
            )
        }
    }

    private func orderRow(index: Int, source: ProjectMergeSource) -> some View {
        HStack(spacing: 10) {
            Text("\(index + 1)")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.accentColor))

            Text(source.name)
                .font(.system(size: 13))
                .lineLimit(1)

            Spacer()

            Button(action: { move(from: index, to: index - 1) }) {
                Image(systemName: "chevron.up")
            }
            .buttonStyle(BorderlessButtonStyle())
            .disabled(index == 0)

            Button(action: { move(from: index, to: index + 1) }) {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(BorderlessButtonStyle())
            .disabled(index == sources.count - 1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var progressSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(mergeManager.statusText)
                .font(.system(size: 12))
                .foregroundColor(.secondary)

            ProgressView(value: mergeManager.progress)
                .progressViewStyle(LinearProgressViewStyle())

            Text("\(Int(mergeManager.progress * 100))%")
                .font(.system(size: 11))
                .foregroundColor(.secondary)

            Text(^String.Titles.mergeProjectsKeepOpenHint)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
    }

    private var footer: some View {
        HStack {
            Spacer()

            Button(^String.Titles.cancelButtonTitle) {
                if mergeManager.isMerging {
                    mergeManager.cancel()
                } else {
                    onCancel()
                }
            }

            Button(^String.Titles.mergeProjectsStartButton) {
                startMerge()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(mergeManager.isMerging || sources.count < 2 || projectName.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    // MARK: - Действия

    private func move(from index: Int, to newIndex: Int) {
        guard sources.indices.contains(index), sources.indices.contains(newIndex) else { return }
        sources.swapAt(index, newIndex)
    }

    private func startMerge() {
        errorMessage = nil

        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType.quickTimeMovie]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.title = ^String.Titles.mergeProjectsSavePanelTitle
        panel.message = ^String.Titles.mergeProjectsSavePanelMessage
        panel.nameFieldStringValue = "\(sanitizedFileName).mov"

        guard panel.runModal() == .OK, let outputURL = panel.url else { return }

        let options = ProjectMergeOptions(
            projectName: projectName.trimmingCharacters(in: .whitespaces),
            mergedLineNames: mergedNameSelection
        )

        viewModel.mergeProjects(sources: sources, options: options, outputURL: outputURL) { result in
            switch result {
            case .success(let file):
                onFinished(file)
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
        }
    }

    private var sanitizedFileName: String {
        let trimmed = projectName.trimmingCharacters(in: .whitespaces)
        let invalid = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        let cleaned = trimmed.components(separatedBy: invalid).joined(separator: "-")
        return cleaned.isEmpty ? "merged" : cleaned
    }

    private static func defaultName(for sources: [ProjectMergeSource]) -> String {
        let names = sources.map(\.name)
        guard let first = names.first else { return ^String.Titles.mergeProjectsDefaultName }
        if names.count == 1 { return first }
        return "\(first) +\(names.count - 1)"
    }
}
